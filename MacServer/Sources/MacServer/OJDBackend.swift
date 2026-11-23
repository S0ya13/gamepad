import Foundation
import SharedProtocol

/// Real analog gamepad for games: pipes the state into OpenJoystickDriver's `ojd virtual feed`,
/// which publishes a virtual Xbox-style controller (we can't: virtual HID needs an Apple-granted entitlement).
final class OJDBackend: InputBackend {
    static let profiles = ["sdl": "sdl-compatible", "gc": "game-controller-compatible", "generic": "generic"]

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

    init(profile: String) {
        signal(SIGPIPE, SIG_IGN)  // a dead ojd must not kill us mid-write; terminationHandler reports it
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ojd", "--no-input", "virtual", "feed", "--as", profile]
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice  // rumble commands from games; not used
        process.terminationHandler = { p in
            DispatchQueue.main.async {
                print("\nojd virtual feed exited (\(p.terminationStatus)). Is OpenJoystickDriver running, with Input Monitoring and Accessibility allowed? Try: ojd status")
                exit(1)
            }
        }
        do {
            try process.run()
        } catch {
            print("cannot start ojd: \(error). Install OpenJoystickDriver and link the CLI as 'ojd' on PATH.")
            exit(1)
        }
    }

    func apply(_ packet: GamepadPacket) { write(Self.frame(for: packet)) }

    func reset() { write("{}") }

    private func write(_ line: String) {
        guard line != lastLine else { return }  // heartbeats repeat the state; ojd keeps the pad alive itself
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
