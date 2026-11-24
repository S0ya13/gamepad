import Foundation
import os
import SharedProtocol

/// Real analog gamepad for games: pipes the state into OpenJoystickDriver's `ojd virtual feed`,
/// which publishes a virtual Xbox-style controller (we can't: virtual HID needs an Apple-granted entitlement).
public final class OJDBackend: InputBackend {
    public static let profiles = ["sdl": "sdl-compatible", "gc": "game-controller-compatible", "generic": "generic"]

    private static let buttons: [(GamepadPacket.Buttons, String)] = [
        (.a, "South"), (.b, "East"), (.x, "West"), (.y, "North"),
        (.l3, "LeftStickClick"), (.r3, "RightStickClick"),
        (.lb, "LeftShoulder"), (.rb, "RightShoulder"), (.start, "Start"), (.back, "Back"),
    ]
    private static let dpad: [(GamepadPacket.Buttons, String)] = [
        (.dpadUp, "DpadUp"), (.dpadDown, "DpadDown"), (.dpadLeft, "DpadLeft"), (.dpadRight, "DpadRight"),
    ]

    private let profile: String
    private var process: Process?
    private var input: Pipe?
    private var lastLine = ""
    private var lastWrite: UInt64 = 0
    private var stopping = false
    private var rumbleGeneration = 0
    // Once a second while the phone sends: what reached ojd. Read with `log stream --level debug --predicate 'subsystem == "com.gamepad.mac"'`.
    private var stats = (applied: 0, written: 0, skipped: 0, rumbles: 0, since: UInt64(0))
    private static let log = Logger(subsystem: "com.gamepad.mac", category: "ojd")
    private let onFailure: (String) -> Void
    private let onRecovered: () -> Void
    private let onRumble: (UInt8, UInt8) -> Void

    /// OJD hands back game output only when it gets input; resend the held state at least this often.
    private static let feedbackInterval: UInt64 = 40_000_000
    /// OJD closes a feed whose frame it couldn't deliver (seen when a GeForce NOW game starts); start a new one after this.
    static var restartDelay: TimeInterval = 1

    /// `onFailure` runs on the main queue when `ojd` can't start or exits on its own; a feed that exits is
    /// started again, and `onRecovered` runs once the new one is up.
    /// `onRumble` gets the game's motor levels (heavy, light; 0...255) on the main queue.
    public init(profile: String, onFailure: @escaping (String) -> Void, onRecovered: @escaping () -> Void = {},
                onRumble: @escaping (UInt8, UInt8) -> Void = { _, _ in }) {
        self.profile = profile
        self.onFailure = onFailure
        self.onRecovered = onRecovered
        self.onRumble = onRumble
        signal(SIGPIPE, SIG_IGN)  // a dead ojd must not kill us mid-write; terminationHandler reports it
        launch(restart: false)
    }

    deinit {
        stopping = true
        if process?.isRunning == true { process?.terminate() }  // removes the virtual gamepad
    }

    private func launch(restart: Bool) {
        guard !stopping else { return }
        guard let ojd = Self.ojdPath() else {
            DispatchQueue.main.async { [onFailure] in onFailure("ojd not found. Install OpenJoystickDriver and link its CLI as 'ojd' (Settings → Advanced → Install Command-Line Tool).") }
            return
        }
        let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: ojd)  // a link named "ojd": the app runs as its CLI by argv[0]
        // The default 0.5 s per service request is too short while a game streams: the service answers late and
        // the feed quits, so the pad reconnects over and over. A late answer only delays the frames.
        process.arguments = ["--no-input", "--timeout", "10", "virtual", "feed", "--as", profile]
        process.standardInput = input
        process.standardOutput = output  // games' output commands, one JSON object per line
        process.standardError = errors
        // A stalled ojd stops reading; a blocking write would then freeze the main queue and with it the UDP replies.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETFL, O_NONBLOCK)
        var pending = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // End of file: without this the handler fires nonstop and burns a core.
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex ..< newline]
                pending = Data(pending[(newline + 1)...])
                guard let rumble = Self.rumble(fromLine: Data(line)) else { continue }
                DispatchQueue.main.async { self?.rumble(rumble) }
            }
        }
        process.terminationHandler = { [weak self] p in
            // ojd has exited, so its stderr ends here; it holds the reason, such as "The service closed the virtual gamepad".
            let reason = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(whereSeparator: \.isNewline).last.map(String.init) ?? "no message"
            DispatchQueue.main.async {
                // No self: the backend was released (mode switch, quit) and deinit killed ojd on purpose.
                guard let self, !self.stopping, self.process === p else { return }
                Self.log.error("ojd virtual feed exited (\(p.terminationStatus, privacy: .public)): \(reason, privacy: .public)")
                self.onFailure("ojd virtual feed exited (\(p.terminationStatus)): \(reason) Restarting it…")
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
                    self?.launch(restart: true)
                }
            }
        }
        do {
            try process.run()
            self.process = process
            self.input = input
            lastLine = ""  // the new feed starts neutral; send the held state again
            // Recovered only if it stays up: an ojd that exits at once (service stopped) would make the error blink.
            if restart {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2 * Self.restartDelay) { [weak self, weak process] in
                    guard let self, let process, self.process === process, process.isRunning else { return }
                    self.onRecovered()
                }
            }
        } catch {
            DispatchQueue.main.async { [onFailure] in onFailure("Cannot start ojd: \(error). Install OpenJoystickDriver and link its CLI as 'ojd' on PATH.") }
        }
    }

    /// An app started from Finder has a minimal PATH, so also look where OJD and users put the link.
    public static func ojdPath() -> String? {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let dirs = path + ["/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin"]
        return dirs.map { $0 + "/ojd" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The feed's process while it runs; tests kill it to check the restart.
    var runningPID: pid_t? { process?.isRunning == true ? process?.processIdentifier : nil }

    public func apply(_ packet: GamepadPacket) {
        stats.applied += 1
        let now = DispatchTime.now().uptimeNanoseconds
        if now - stats.since >= 1_000_000_000 {
            if stats.since > 0 {
                Self.log.debug("""
                    packets \(self.stats.applied, privacy: .public) written \(self.stats.written, privacy: .public) \
                    skipped \(self.stats.skipped, privacy: .public) rumbles \(self.stats.rumbles, privacy: .public) \
                    lx \(packet.lx, privacy: .public) buttons \(packet.buttons.rawValue, privacy: .public)
                    """)
            }
            stats = (0, 0, 0, 0, now)
        }
        write(Self.frame(for: packet))
    }

    public func reset() { write("{}") }

    private func write(_ line: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let process, process.isRunning, let input,
              line != lastLine || now - lastWrite > Self.feedbackInterval else { return }
        let bytes = Array((line + "\n").utf8)
        // A line is under PIPE_BUF (512 bytes), so a non-blocking write puts all of it in the pipe or none.
        // None: ojd is behind; the next packet or heartbeat (50 ms) tries again.
        let written = bytes.withUnsafeBytes { Darwin.write(input.fileHandleForWriting.fileDescriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else { stats.skipped += 1; return }
        stats.written += 1
        lastLine = line
        lastWrite = now
    }

    /// A timed rumble stops by itself; a newer command cancels the pending stop.
    private func rumble(_ r: (low: UInt8, high: UInt8, milliseconds: Int?)) {
        stats.rumbles += 1
        rumbleGeneration += 1
        let generation = rumbleGeneration
        onRumble(r.low, r.high)
        guard let ms = r.milliseconds, r.low > 0 || r.high > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms + 40)) { [weak self] in
            guard let self, self.rumbleGeneration == generation else { return }
            self.onRumble(0, 0)
        }
    }

    /// `{"type":"SetRumble","intensities":{"lowFrequency":0...65535,"highFrequency":...},"durationMilliseconds":n}`
    /// or `{"type":"StopRumble"}` → motor levels 0...255. Nil for anything else (rumble is optional).
    static func rumble(fromLine line: Data) -> (low: UInt8, high: UInt8, milliseconds: Int?)? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        switch message["type"] as? String {
        case "StopRumble":
            return (0, 0, nil)
        case "SetRumble":
            let levels = message["intensities"] as? [String: Any] ?? [:]
            func motor(_ name: String) -> UInt8 {
                UInt8(min(max((levels[name] as? Int) ?? 0, 0), 65535) / 257)
            }
            let ms = (message["durationMilliseconds"] as? Int).map { min(max($0, 0), 60000) }
            return (motor("lowFrequency"), motor("highFrequency"), ms)
        default:
            return nil
        }
    }

    /// One `ojd virtual feed` line. OJD sticks are -1...1 with Y down (ours are Y up), triggers 0...1.
    static func frame(for p: GamepadPacket) -> String {
        func names(_ table: [(GamepadPacket.Buttons, String)]) -> String {
            table.filter { p.buttons.contains($0.0) }.map { "\"\($0.1)\"" }.joined(separator: ",")
        }
        func axis(_ raw: Int16, flip: Bool = false) -> String {
            String(format: "%.4f", (flip ? -1 : 1) * GamepadPacket.unit(raw))
        }
        func trigger(_ raw: UInt8) -> String { String(format: "%.4f", Double(raw) / 255) }
        return "{\"buttons\":[\(names(buttons))],\"dpad\":[\(names(dpad))],\"axes\":{"
            + "\"LeftStickX\":\(axis(p.lx)),\"LeftStickY\":\(axis(p.ly, flip: true)),"
            + "\"RightStickX\":\(axis(p.rx)),\"RightStickY\":\(axis(p.ry, flip: true)),"
            + "\"LeftTrigger\":\(trigger(p.lt)),\"RightTrigger\":\(trigger(p.rt))}}"
    }
}
