import CryptoKit
import Foundation

/// Every control a phone layout can place; also what a keyboard mapping maps from.
public enum Control: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case a, b, x, y, up, down, left, right, lb, rb, lt, rt, l3, r3, start, back

    /// Digital bit; nil for the analog triggers.
    public var button: GamepadPacket.Buttons? {
        switch self {
        case .a: .a
        case .b: .b
        case .x: .x
        case .y: .y
        case .up: .dpadUp
        case .down: .dpadDown
        case .left: .dpadLeft
        case .right: .dpadRight
        case .lb: .lb
        case .rb: .rb
        case .l3: .l3
        case .r3: .r3
        case .start: .start
        case .back: .back
        case .lt, .rt: nil
        }
    }

    public var title: String {
        switch self {
        case .up: "▲"
        case .down: "▼"
        case .left: "◀"
        case .right: "▶"
        case .start: "Start"
        case .back: "Back"
        default: rawValue.uppercased()
        }
    }
}

/// Keyboard & mouse mode: which key each control presses and what each stick does.
/// Lives in the phone's game profile and is sent to the Mac, so every game gets its own keys.
public struct KeyMap: Codable, Equatable, Sendable {
    public enum Stick: String, Codable, CaseIterable, Sendable {
        case wasd, arrows, mouse, none

        public var title: String {
            switch self {
            case .wasd: "W A S D"
            case .arrows: "Arrow keys"
            case .mouse: "Mouse"
            case .none: "Nothing"
            }
        }
    }

    /// Control → one of `keyNames`; a missing control presses nothing.
    public var keys: [Control: String]
    public var leftStick: Stick
    public var rightStick: Stick

    public init(keys: [Control: String], leftStick: Stick, rightStick: Stick) {
        self.keys = keys
        self.leftStick = leftStick
        self.rightStick = rightStick
    }

    public static let standard = KeyMap(keys: [
        .a: "Space", .b: "F", .x: "R", .y: "E",
        .up: "1", .down: "2", .left: "3", .right: "4",
        .lb: "Q", .rb: "G", .lt: "Mouse Right", .rt: "Mouse Left",
        .l3: "Shift", .r3: "V", .start: "Escape", .back: "Tab",
    ], leftStick: .wasd, rightStick: .mouse)

    /// Everything the Mac can press; it rejects nothing, unknown names just press nothing.
    public static let keyNames: [String] =
        ["Mouse Left", "Mouse Right", "Mouse Middle", "Space", "Return", "Tab", "Escape", "Delete",
         "Shift", "Control", "Option", "Command", "Up", "Down", "Left", "Right"]
        + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map(String.init)

    private static let kind: UInt8 = 0x4B  // "K"
    private static let maxSize = 2048

    /// Version, "K", JSON, truncated HMAC. Always longer than a sealed packet, so the Mac tells them apart by size.
    public func sealed(key: SymmetricKey) -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = [protocolVersion, Self.kind] + Array((try? encoder.encode(self)) ?? Data())
        return body + Array(HMAC<SHA256>.authenticationCode(for: body, using: key)).prefix(8)
    }

    /// Nil unless the version, kind and HMAC match and the JSON decodes (untrusted network input).
    // shortcut: no seq, so someone on the LAN can replay an older mapping of the same phone; add one if that matters.
    public init?<C: Collection>(sealed bytes: C, key: SymmetricKey) where C.Element == UInt8 {
        let b = Array(bytes)
        guard b.count > GamepadPacket.sealedSize, b.count <= Self.maxSize, b[0] == protocolVersion, b[1] == Self.kind,
              tagMatches(b, bodyCount: b.count - 8, key: key),
              let map = try? JSONDecoder().decode(KeyMap.self, from: Data(b[2 ..< b.count - 8])) else { return nil }
        self = map
    }
}
