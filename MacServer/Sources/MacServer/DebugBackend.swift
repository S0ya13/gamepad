import Foundation
import GamepadServerKit
import SharedProtocol

final class DebugBackend: InputBackend {
    private static let names: [(GamepadPacket.Buttons, String)] = [
        (.dpadUp, "↑"), (.dpadDown, "↓"), (.dpadLeft, "←"), (.dpadRight, "→"),
        (.a, "A"), (.b, "B"), (.x, "X"), (.y, "Y"), (.l3, "L3"), (.r3, "R3"),
        (.lb, "LB"), (.rb, "RB"), (.start, "Start"), (.back, "Back"),
    ]

    func apply(_ p: GamepadPacket) {
        let pressed = Self.names.filter { p.buttons.contains($0.0) }.map(\.1).joined(separator: " ")
        let axes = String(format: "L(%+.2f %+.2f)  R(%+.2f %+.2f)  LT %.2f  RT %.2f",
                          GamepadPacket.unit(p.lx), GamepadPacket.unit(p.ly),
                          GamepadPacket.unit(p.rx), GamepadPacket.unit(p.ry),
                          Double(p.lt) / 255, Double(p.rt) / 255)
        draw("#\(p.seq)  \(axes)  [\(pressed)]")
    }

    func use(_ keys: KeyMap) {
        let list = Control.allCases.compactMap { c in keys.keys[c].map { "\(c.title) \($0)" } }.joined(separator: " · ")
        print("\nkeys: left stick \(keys.leftStick.title) · right stick \(keys.rightStick.title) · \(list)")
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
