import Foundation
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

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private var lastLine = ""
    private var lastWrite: UInt64 = 0
    private var stopping = false
    private var rumbleGeneration = 0
    private let onRumble: (UInt8, UInt8) -> Void

    /// OJD hands back game output only when it gets input; resend the held state at least this often.
    private static let feedbackInterval: UInt64 = 40_000_000

    /// `onFailure` runs on the main queue when `ojd` can't start or exits on its own.
    /// `onRumble` gets the game's motor levels (heavy, light; 0...255) on the main queue.
    public init(profile: String, onFailure: @escaping (String) -> Void,
                onRumble: @escaping (UInt8, UInt8) -> Void = { _, _ in }) {
        self.onRumble = onRumble
        signal(SIGPIPE, SIG_IGN)  // a dead ojd must not kill us mid-write; terminationHandler reports it
        guard let ojd = Self.ojdPath() else {
            DispatchQueue.main.async { onFailure("ojd not found. Install OpenJoystickDriver and link its CLI as 'ojd' (Settings → Advanced → Install Command-Line Tool).") }
            return
        }
        process.executableURL = URL(fileURLWithPath: ojd)  // a link named "ojd": the app runs as its CLI by argv[0]
        process.arguments = ["--no-input", "virtual", "feed", "--as", profile]
        process.standardInput = stdin
        process.standardOutput = stdout  // games' output commands, one JSON object per line
        var pending = Data()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            pending.append(handle.availableData)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex ..< newline]
                pending = Data(pending[(newline + 1)...])
                guard let rumble = Self.rumble(fromLine: Data(line)) else { continue }
                DispatchQueue.main.async { self?.rumble(rumble) }
            }
        }
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                // No self: the backend was released (mode switch, quit) and deinit killed ojd on purpose.
                guard let self, !self.stopping else { return }
                onFailure("ojd virtual feed exited (\(p.terminationStatus)). Is OpenJoystickDriver running, with Input Monitoring allowed? Try: ojd status")
            }
        }
        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { onFailure("Cannot start ojd: \(error). Install OpenJoystickDriver and link its CLI as 'ojd' on PATH.") }
        }
    }

    deinit {
        stdout.fileHandleForReading.readabilityHandler = nil
        stopping = true
        if process.isRunning { process.terminate() }  // removes the virtual gamepad
    }

    /// An app started from Finder has a minimal PATH, so also look where OJD and users put the link.
    public static func ojdPath() -> String? {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let dirs = path + ["/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin"]
        return dirs.map { $0 + "/ojd" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func apply(_ packet: GamepadPacket) { write(Self.frame(for: packet)) }

    public func reset() { write("{}") }

    private func write(_ line: String) {
        // Not running: nobody drains the pipe, and a full pipe would block the main thread.
        let now = DispatchTime.now().uptimeNanoseconds
        guard process.isRunning, line != lastLine || now - lastWrite > Self.feedbackInterval else { return }
        lastLine = line
        lastWrite = now
        try? stdin.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    /// A timed rumble stops by itself; a newer command cancels the pending stop.
    private func rumble(_ r: (low: UInt8, high: UInt8, milliseconds: Int?)) {
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
