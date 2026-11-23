import CoreGraphics
import Foundation
import SharedProtocol

/// Pure multitouch logic: touch ids + points in, GamepadPacket out. No UIKit, so it is unit-testable.
final class TouchEngine {
    typealias Buttons = GamepadPacket.Buttons

    struct Stick {
        let touch: ObjectIdentifier
        var center: CGPoint
        var position: CGPoint
    }

    var size: CGSize = .zero
    /// The profile's controls; a touch anywhere else is a floating stick (left or right half). Later ones are on top.
    var layout: [Profile.Placed] = [] {
        // A latched button that was removed or stopped being a toggle lets go.
        didSet { latched.formIntersection(layout.filter(\.toggle).map(\.id)) }
    }
    var leftSetup = Profile.StickSetup.left
    var rightSetup = Profile.StickSetup.right
    var stickRadius: CGFloat = 70
    /// Deflection (0...1) below which the stick reads 0; the rest is rescaled so full deflection still gives 1.
    var deadZone: CGFloat = 0
    /// Left-stick deflection (0...1) that holds L3.
    var l3Threshold: CGFloat = 0.88
    private static let l3Hysteresis: CGFloat = 0.04  // a trembling finger on the ring must not buzz the haptic
    /// Steering from tilting the phone (-1...1); replaces the left stick's X while set.
    var tilt: Double?
    /// Phone rotation that gives full lock.
    static let steeringLock = Double.pi / 4

    private(set) var left: Stick?
    private(set) var right: Stick?
    private(set) var l3 = false
    private var buttonTouches: [ObjectIdentifier: Control] = [:]
    /// Toggle buttons currently held down by an earlier tap.
    private var latched: Set<UUID> = []
    private var triggerTouches: [ObjectIdentifier: (control: Control, frame: CGRect, pull: Double)] = [:]

    /// Returns true when a control went down (caller fires the haptic).
    func began(_ touch: ObjectIdentifier, at p: CGPoint) -> Bool {
        if let hit = layout.last(where: { contains(frame(of: $0), p) }) {
            let f = frame(of: hit)
            if hit.control.button == nil {
                triggerTouches[touch] = (hit.control, f, Self.pull(at: p, in: f))
            } else if hit.toggle {
                if latched.remove(hit.id) == nil { latched.insert(hit.id) }
            } else {
                buttonTouches[touch] = hit.control
            }
            return true
        }
        // A stick; a second finger in an already active stick zone is ignored.
        let isLeft = p.x < size.width / 2
        guard (isLeft ? left : right) == nil else { return false }
        let setup = isLeft ? leftSetup : rightSetup
        var center = p
        if setup.mode == .fixed {
            // Only near the base, so a stray touch far away can't throw the stick to full deflection.
            center = rest(setup)
            guard hypot(p.x - center.x, p.y - center.y) <= stickRadius * 2 else { return false }
        }
        let stick = Stick(touch: touch, center: center, position: p)
        if isLeft { left = stick } else { right = stick }
        return false
    }

    /// Returns true when the left stick crosses the L3 ring outward (caller fires the haptic).
    /// A touch stays bound to the stick/button/trigger it began on, wherever it moves (pointer capture).
    func moved(_ touch: ObjectIdentifier, to p: CGPoint) -> Bool {
        if var t = triggerTouches[touch] {
            t.pull = Self.pull(at: p, in: t.frame)
            triggerTouches[touch] = t
        }
        if right?.touch == touch { right = follow(right!, to: p, rightSetup) }
        guard let stick = left, stick.touch == touch else { return false }
        left = follow(stick, to: p, leftSetup)
        let wasL3 = l3
        l3 = deflection(left!) > (wasL3 ? l3Threshold - Self.l3Hysteresis : l3Threshold)
        return l3 && !wasL3
    }

    func ended(_ touch: ObjectIdentifier) {
        if left?.touch == touch { left = nil; l3 = false }
        if right?.touch == touch { right = nil }
        buttonTouches[touch] = nil
        triggerTouches[touch] = nil
    }

    /// Current state; `seq` is filled in by the sender.
    var packet: GamepadPacket {
        var buttons = buttonTouches.values.reduce(into: Buttons()) { $0.formUnion($1.button ?? []) }
        for placed in layout where latched.contains(placed.id) { buttons.formUnion(placed.control.button ?? []) }
        if l3 { buttons.insert(.l3) }
        let l = axes(left), r = axes(right)
        return GamepadPacket(buttons: buttons,
                             lx: GamepadPacket.axis(tilt ?? l.x), ly: GamepadPacket.axis(l.y),
                             rx: GamepadPacket.axis(r.x), ry: GamepadPacket.axis(r.y),
                             lt: GamepadPacket.trigger(pull(.lt)), rt: GamepadPacket.trigger(pull(.rt)))
    }

    /// A control's rectangle in points.
    func frame(of placed: Profile.Placed) -> CGRect {
        CGRect(x: placed.frame.minX * size.width, y: placed.frame.minY * size.height,
               width: placed.frame.width * size.width, height: placed.frame.height * size.height)
    }

    /// A stick's resting spot in points.
    func rest(_ setup: Profile.StickSetup) -> CGPoint {
        CGPoint(x: setup.center.x * size.width, y: setup.center.y * size.height)
    }

    /// Finger position clamped to the ring (drawn as is, without the dead zone).
    func knob(_ s: Stick) -> CGPoint {
        let dx = s.position.x - s.center.x, dy = s.position.y - s.center.y
        let length = hypot(dx, dy)
        guard length > stickRadius else { return s.position }
        return CGPoint(x: s.center.x + dx / length * stickRadius, y: s.center.y + dy / length * stickRadius)
    }

    /// Steering from gravity in device coordinates: turning the phone clockwise (like a wheel) steers right.
    static func steering(gravityX gx: Double, gravityY gy: Double, landscapeRight: Bool) -> Double {
        // landscapeRight: the phone's top points left, so gravity is -x when level; landscapeLeft: +x.
        let angle = landscapeRight ? atan2(-gy, -gx) : atan2(gy, gx)
        return min(max(angle / steeringLock, -1), 1)
    }

    /// Dynamic: past the ring, the base is dragged along so it stays one radius behind the finger.
    private func follow(_ s: Stick, to p: CGPoint, _ setup: Profile.StickSetup) -> Stick {
        var s = s
        s.position = p
        let dx = p.x - s.center.x, dy = p.y - s.center.y, length = hypot(dx, dy)
        if setup.mode == .dynamic, length > stickRadius {
            s.center = CGPoint(x: p.x - dx / length * stickRadius, y: p.y - dy / length * stickRadius)
        }
        return s
    }

    /// Edges count, so a touch on the line between two cells still hits (the later one).
    private func contains(_ r: CGRect, _ p: CGPoint) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }

    /// Like a pedal: the lower the finger in the trigger, the harder the pull. A touch at the top still
    /// gives a quarter, so a quick tap counts as pressed in any game.
    private static func pull(at p: CGPoint, in f: CGRect) -> Double {
        0.25 + 0.75 * min(max((p.y - f.minY) / f.height, 0), 1)
    }

    private func pull(_ trigger: Control) -> Double {
        triggerTouches.values.filter { $0.control == trigger }.map(\.pull).max() ?? 0
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
