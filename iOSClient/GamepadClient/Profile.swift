import CoreGraphics
import Foundation
import SharedProtocol

/// One game's setup: which controls are on screen and where, tilt steering, and keyboard keys for the Mac.
struct Profile: Codable, Equatable, Identifiable {
    struct Placed: Codable, Equatable, Identifiable {
        var id = UUID()
        var control: Control
        /// In 0...1 of the screen, so a layout fits any iPhone.
        var frame: CGRect
    }

    var id = UUID()
    var name: String
    var controls: [Placed]
    /// Racing: tilting the phone like a wheel steers (left stick X).
    var tilt = false
    var keys = KeyMap.standard

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
