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

        var mode = Mode.dynamic
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
    var theme = Theme.midnight

    /// The original layout: D-pad and ABXY as 2×2 grids over the top 40%, floating sticks below.
    static let standard = Profile(name: "Standard", controls: grid([.left, .up, .down, .right], x: 0)
        + grid([.x, .y, .a, .b], x: 0.5))

    /// Laid out like a real controller: shoulders on top, D-pad cross, ABXY diamond, Back/Start between.
    static let controller: Profile = {
        // Square cells on a ~2.17:1 landscape screen: height = width * 2.17.
        func cell(_ control: Control, _ cx: Double, _ cy: Double, _ w: Double, _ shape: Placed.Shape) -> Placed {
            let h = w * 2.17
            return Placed(control: control, frame: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), shape: shape)
        }
        let d = 0.062, f = 0.074  // D-pad cell, face button
        let pad = [(Control.up, 0.0, -1.0), (.down, 0, 1), (.left, -1, 0), (.right, 1, 0)].map { c, dx, dy in
            cell(c, 0.16 + dx * d, 0.45 + dy * d * 2.17, d, .rounded)
        }
        let face = [(Control.y, 0.0, -1.0), (.a, 0, 1), (.x, -1, 0), (.b, 1, 0)].map { c, dx, dy in
            cell(c, 0.84 + dx * f * 1.05, 0.45 + dy * f * 2.17 * 1.05, f, .circle)
        }
        let top: [Placed] = [
            Placed(control: .lt, frame: CGRect(x: 0, y: 0, width: 0.13, height: 0.15), shape: .rounded),
            Placed(control: .lb, frame: CGRect(x: 0.13, y: 0, width: 0.13, height: 0.15), shape: .rounded),
            Placed(control: .back, frame: CGRect(x: 0.4, y: 0.02, width: 0.09, height: 0.11), shape: .rounded),
            Placed(control: .start, frame: CGRect(x: 0.51, y: 0.02, width: 0.09, height: 0.11), shape: .rounded),
            Placed(control: .rb, frame: CGRect(x: 0.74, y: 0, width: 0.13, height: 0.15), shape: .rounded),
            Placed(control: .rt, frame: CGRect(x: 0.87, y: 0, width: 0.13, height: 0.15), shape: .rounded),
        ]
        return Profile(name: "Controller", controls: top + pad + face,
                       leftStick: StickSetup(center: CGPoint(x: 0.36, y: 0.66)),
                       rightStick: StickSetup(center: CGPoint(x: 0.64, y: 0.66)))
    }()

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
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .midnight
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

    /// The button's own colour, else the theme's.
    func uiColor(_ theme: Profile.Theme) -> UIColor {
        color.flatMap(UIColor.init(hex:)) ?? theme.color(for: control)
    }
}

extension Profile {
    /// Background and default colours of the pad; a button's own colour still wins.
    enum Theme: String, Codable, CaseIterable {
        case midnight, black, neon, sunset, mono

        var title: String {
            switch self {
            case .midnight: "Midnight"
            case .black: "Black (saves battery)"
            case .neon: "Neon"
            case .sunset: "Sunset"
            case .mono: "Mono"
            }
        }

        var background: UIColor {
            switch self {
            case .midnight: UIColor(hex: "#090A0E")!
            case .black, .mono: .black
            case .neon: UIColor(hex: "#0C0618")!
            case .sunset: UIColor(hex: "#160A08")!
            }
        }

        /// Buttons without a colour of their own, and the sticks.
        var accent: UIColor {
            switch self {
            case .midnight, .black, .mono: .white
            case .neon: UIColor(hex: "#3DF5FF")!
            case .sunset: UIColor(hex: "#FFB86B")!
            }
        }

        var stick: UIColor {
            switch self {
            case .neon: UIColor(hex: "#FF4FD8")!
            case .sunset: UIColor(hex: "#FFD36B")!
            default: .white
            }
        }

        /// A B X Y keep their usual colours, toned to the theme; Mono leaves them plain.
        func color(for control: Control) -> UIColor {
            let face: [Control: String]
            switch self {
            case .mono: face = [:]
            case .neon: face = [.a: "#39FF88", .b: "#FF3D6E", .x: "#3D8BFF", .y: "#FFF03D"]
            case .sunset: face = [.a: "#9BE15D", .b: "#FF5E3A", .x: "#5EC8FF", .y: "#FFC93D"]
            default: face = [.a: "#4DD973", .b: "#FF544D", .x: "#4099FF", .y: "#FFD133"]
            }
            return face[control].flatMap(UIColor.init(hex:)) ?? accent
        }
    }
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
