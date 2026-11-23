import CoreGraphics
import Foundation
import SharedProtocol
import UIKit

/// One game's setup: which controls are on screen and where, how they look, the sticks, tilt steering,
/// and keyboard keys for the Mac.
struct Profile: Codable, Equatable, Identifiable {
    struct Placed: Codable, Equatable, Identifiable {
        enum Shape: String, Codable, CaseIterable { case square, rounded, circle }

        var id = UUID()
        var control: Control
        /// In 0...1 of the screen, so a layout fits any iPhone.
        var frame: CGRect
        /// Text on the button; nil shows the control's name.
        var label: String?
        var shape = Shape.square
        /// "#RRGGBB"; nil is white.
        var color: String?
        /// Tap once to hold the button down, tap again to let go (buttons only, not triggers).
        var toggle = false

        var title: String { label.flatMap { $0.isEmpty ? nil : $0 } ?? control.title }
    }

    /// Where a stick rests and how its base moves with the finger.
    struct StickSetup: Codable, Equatable {
        enum Mode: String, Codable, CaseIterable {
            /// The base stays at its spot; a touch near it moves the knob.
            case fixed
            /// The base appears where the finger lands, anywhere in its half.
            case floating
            /// Like floating, and the base follows the finger when it runs past the ring.
            case dynamic
        }

        var mode = Mode.floating
        /// Resting spot in 0...1 of the screen, kept in the stick's half.
        var center: CGPoint

        static let left = StickSetup(center: CGPoint(x: 0.25, y: 0.7))
        static let right = StickSetup(center: CGPoint(x: 0.75, y: 0.7))
    }

    var id = UUID()
    var name: String
    var controls: [Placed]
    /// Racing: tilting the phone like a wheel steers (left stick X).
    var tilt = false
    var keys = KeyMap.standard
    var leftStick = StickSetup.left
    var rightStick = StickSetup.right

    /// The original layout: D-pad and ABXY as 2×2 grids over the top 40%, floating sticks below.
    static let standard = Profile(name: "Standard", controls: grid([.left, .up, .down, .right], x: 0)
        + grid([.x, .y, .a, .b], x: 0.5))

    /// Tilt to steer, pedals on the sides: LT brake on the left, RT gas on the right.
    static let racing = Profile(
        name: "Racing",
        controls: [Control.lb, .x, .y, .a, .b, .rb].enumerated().map { i, control in
            Placed(control: control, frame: CGRect(x: Double(i) / 6, y: 0, width: 1.0 / 6, height: 0.25))
        } + [
            Placed(control: .lt, frame: CGRect(x: 0, y: 0.25, width: 0.2, height: 0.75)),
            Placed(control: .rt, frame: CGRect(x: 0.8, y: 0.25, width: 0.2, height: 0.75)),
        ],
        tilt: true)

    private static func grid(_ controls: [Control], x: Double) -> [Placed] {
        controls.enumerated().map { i, control in
            Placed(control: control, frame: CGRect(x: x + Double(i % 2) * 0.25, y: Double(i / 2) * 0.2, width: 0.25, height: 0.2))
        }
    }
}

// Profiles saved by older builds lack the newer fields; they get the defaults instead of failing to load
// (a failed load would replace the user's layouts with the built-in ones).
extension Profile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        controls = try c.decode([Placed].self, forKey: .controls)
        tilt = try c.decodeIfPresent(Bool.self, forKey: .tilt) ?? false
        keys = try c.decodeIfPresent(KeyMap.self, forKey: .keys) ?? .standard
        leftStick = try c.decodeIfPresent(StickSetup.self, forKey: .leftStick) ?? .left
        rightStick = try c.decodeIfPresent(StickSetup.self, forKey: .rightStick) ?? .right
    }
}

extension Profile.Placed {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        control = try c.decode(Control.self, forKey: .control)
        frame = try c.decode(CGRect.self, forKey: .frame)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape) ?? .square
        color = try c.decodeIfPresent(String.self, forKey: .color)
        toggle = try c.decodeIfPresent(Bool.self, forKey: .toggle) ?? false
    }

    var uiColor: UIColor { color.flatMap(UIColor.init(hex:)) ?? .white }
}

extension UIColor {
    convenience init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
