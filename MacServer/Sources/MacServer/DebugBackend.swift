import Foundation
import SharedProtocol

final class DebugBackend: InputBackend {
    private static let names: [(GamepadPacket.Buttons, String)] = [
        (.dpadUp, "↑"), (.dpadDown, "↓"), (.dpadLeft, "←"), (.dpadRight, "→"),
        (.a, "A"), (.b, "B"), (.x, "X"), (.y, "Y"), (.l3, "L3"), (.r3, "R3"),
    ]

    func apply(_ p: GamepadPacket) {
        let pressed = Self.names.filter { p.buttons.contains($0.0) }.map(\.1).joined(separator: " ")
        let axes = String(format: "L(%+.2f %+.2f)  R(%+.2f %+.2f)",
                          GamepadPacket.unit(p.lx), GamepadPacket.unit(p.ly),
                          GamepadPacket.unit(p.rx), GamepadPacket.unit(p.ry))
        draw("#\(p.seq)  \(axes)  [\(pressed)]")
    }

    func reset() {
        draw("— no client —")
    }

    private func draw(_ line: String) {
        // \r + "erase line" keeps a single updating row.
        print("\r\u{1B}[2K" + line, terminator: "")
        fflush(stdout)
    }
}
