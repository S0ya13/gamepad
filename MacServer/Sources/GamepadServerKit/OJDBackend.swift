import Foundation
import SharedProtocol

/// Real analog gamepad for games: pipes the state into OpenJoystickDriver's `ojd virtual feed`,
/// which publishes a virtual Xbox-style controller (we can't: virtual HID needs an Apple-granted entitlement).
public final class OJDBackend: InputBackend {
    public static let profiles = ["sdl": "sdl-compatible", "gc": "game-controller-compatible", "generic": "generic"]

    private static let buttons: [(GamepadPacket.Buttons, String)] = [
        (.a, "South"), (.b, "East"), (.x, "West"), (.y, "North"),
        (.l3, "LeftStickClick"), (.r3, "RightStickClick"),
    ]
    private static let dpad: [(GamepadPacket.Buttons, String)] = [
        (.dpadUp, "DpadUp"), (.dpadDown, "DpadDown"), (.dpadLeft, "DpadLeft"), (.dpadRight, "DpadRight"),
    ]

    private let process = Process()
    private let stdin = Pipe()
    private var lastLine = ""
    private var stopping = false

    /// `onFailure` runs on the main queue when `ojd` can't start or exits on its own.
    public init(profile: String, onFailure: @escaping (String) -> Void) {
        signal(SIGPIPE, SIG_IGN)  // a dead ojd must not kill us mid-write; terminationHandler reports it
        guard let ojd = Self.ojdPath() else {
            DispatchQueue.main.async { onFailure("ojd not found. Install OpenJoystickDriver and link its CLI as 'ojd' (Settings → Advanced → Install Command-Line Tool).") }
            return
        }
        process.executableURL = URL(fileURLWithPath: ojd)  // a link named "ojd": the app runs as its CLI by argv[0]
        process.arguments = ["--no-input", "virtual", "feed", "--as", profile]
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice  // rumble commands from games; not used
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard self?.stopping != true else { return }
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
        guard process.isRunning, line != lastLine else { return }  // heartbeats repeat; ojd keeps the pad alive
        lastLine = line
        try? stdin.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    /// One `ojd virtual feed` line. OJD sticks are -1...1 with Y down; ours are Y up.
    static func frame(for p: GamepadPacket) -> String {
        func names(_ table: [(GamepadPacket.Buttons, String)]) -> String {
            table.filter { p.buttons.contains($0.0) }.map { "\"\($0.1)\"" }.joined(separator: ",")
        }
        func axis(_ raw: Int16, flip: Bool = false) -> String {
            String(format: "%.4f", (flip ? -1 : 1) * GamepadPacket.unit(raw))
        }
        return "{\"buttons\":[\(names(buttons))],\"dpad\":[\(names(dpad))],\"axes\":{"
            + "\"LeftStickX\":\(axis(p.lx)),\"LeftStickY\":\(axis(p.ly, flip: true)),"
            + "\"RightStickX\":\(axis(p.rx)),\"RightStickY\":\(axis(p.ry, flip: true))}}"
    }
}
