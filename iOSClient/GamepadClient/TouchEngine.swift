import CoreGraphics
import SharedProtocol

/// Pure multitouch logic: touch ids + points in, GamepadPacket out. No UIKit, so it is unit-testable.
final class TouchEngine {
    typealias Buttons = GamepadPacket.Buttons

    struct Stick {
        let touch: ObjectIdentifier
        let center: CGPoint
        var position: CGPoint
    }

    static let buttonZoneFraction: CGFloat = 0.4
    /// D-pad / ABXY diamonds rotated 45° into a 2×2 grid: top-left, top-right, bottom-left, bottom-right.
    static let leftGrid: [Buttons] = [.dpadLeft, .dpadUp, .dpadDown, .dpadRight]
    static let rightGrid: [Buttons] = [.x, .y, .a, .b]

    var size: CGSize = .zero
    var stickRadius: CGFloat = 70
    /// Deflection (0...1) below which the stick reads 0; the rest is rescaled so full deflection still gives 1.
    var deadZone: CGFloat = 0
    /// Left-stick deflection (0...1) that holds L3.
    var l3Threshold: CGFloat = 0.88
    private static let l3Hysteresis: CGFloat = 0.04  // a trembling finger on the ring must not buzz the haptic

    private(set) var left: Stick?
    private(set) var right: Stick?
    private(set) var l3 = false
    private var buttonTouches: [ObjectIdentifier: Buttons] = [:]

    /// Returns true when a button went down (caller fires the haptic).
    func began(_ touch: ObjectIdentifier, at p: CGPoint) -> Bool {
        let isLeft = p.x < size.width / 2
        guard p.y < size.height * Self.buttonZoneFraction else {
            // Floating stick; a second finger in an already active stick zone is ignored.
            let stick = Stick(touch: touch, center: p, position: p)
            if isLeft, left == nil { left = stick } else if !isLeft, right == nil { right = stick }
            return false
        }
        let col = p.x - (isLeft ? 0 : size.width / 2) < size.width / 4 ? 0 : 1
        let row = p.y < size.height * Self.buttonZoneFraction / 2 ? 0 : 1
        buttonTouches[touch] = (isLeft ? Self.leftGrid : Self.rightGrid)[row * 2 + col]
        return true
    }

    /// Returns true when the left stick crosses the L3 ring outward (caller fires the haptic).
    /// A touch stays bound to the stick/button it began on, wherever it moves (pointer capture).
    func moved(_ touch: ObjectIdentifier, to p: CGPoint) -> Bool {
        if right?.touch == touch { right?.position = p }
        guard let stick = left, stick.touch == touch else { return false }
        left?.position = p
        let wasL3 = l3
        l3 = deflection(left!) > (wasL3 ? l3Threshold - Self.l3Hysteresis : l3Threshold)
        return l3 && !wasL3
    }

    func ended(_ touch: ObjectIdentifier) {
        if left?.touch == touch { left = nil; l3 = false }
        if right?.touch == touch { right = nil }
        buttonTouches[touch] = nil
    }

    /// Current state; `seq` is filled in by the sender.
    var packet: GamepadPacket {
        var buttons = buttonTouches.values.reduce(into: Buttons()) { $0.formUnion($1) }
        if l3 { buttons.insert(.l3) }
        let l = axes(left), r = axes(right)
        return GamepadPacket(buttons: buttons,
                             lx: GamepadPacket.axis(l.x), ly: GamepadPacket.axis(l.y),
                             rx: GamepadPacket.axis(r.x), ry: GamepadPacket.axis(r.y))
    }

    /// Finger position clamped to the ring (drawn as is, without the dead zone).
    func knob(_ s: Stick) -> CGPoint {
        let dx = s.position.x - s.center.x, dy = s.position.y - s.center.y
        let length = hypot(dx, dy)
        guard length > stickRadius else { return s.position }
        return CGPoint(x: s.center.x + dx / length * stickRadius, y: s.center.y + dy / length * stickRadius)
    }

    /// Same grid as `began` hit-testing, for drawing.
    func buttonCells() -> [(Buttons, CGRect)] {
        let w = size.width / 4, h = size.height * Self.buttonZoneFraction / 2
        return (Self.leftGrid + Self.rightGrid).enumerated().map { i, button in
            let half = i / 4, cell = i % 4
            return (button, CGRect(x: CGFloat(half * 2 + cell % 2) * w, y: CGFloat(cell / 2) * h, width: w, height: h))
        }
    }

    private func deflection(_ s: Stick) -> CGFloat {
        min(hypot(s.position.x - s.center.x, s.position.y - s.center.y) / stickRadius, 1)
    }

    /// -1...1 per axis, y up, clamped to the ring, with the radial dead zone applied.
    private func axes(_ s: Stick?) -> (x: Double, y: Double) {
        guard let s else { return (0, 0) }
        let dx = s.position.x - s.center.x, dy = s.position.y - s.center.y
        let length = hypot(dx, dy)
        let d = min(length / stickRadius, 1)
        guard length > 0, d > deadZone else { return (0, 0) }
        let scale = (d - deadZone) / (1 - deadZone) / length
        return (Double(dx * scale), Double(-dy * scale))
    }
}
