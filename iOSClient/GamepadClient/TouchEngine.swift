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
        let radius: CGFloat
        /// Camera swipe: the stick reads the finger's speed, not its distance from the center.
        var swipe = false
        var velocity = CGVector.zero
        var time: TimeInterval = 0
    }

    var size: CGSize = .zero
    /// The profile's controls; a touch anywhere else is a floating stick (left or right half). Later ones are on top.
    var layout: [Profile.Placed] = [] {
        // A latched button that was removed or stopped being a toggle lets go.
        didSet {
            let toggles = Set(layout.filter(\.toggle).map(\.id))
            latched = latched.filter { toggles.contains($0.key) }
        }
    }
    var leftSetup = Profile.StickSetup.left
    var rightSetup = Profile.StickSetup.right
    /// Size of sticks that don't set their own.
    var stickRadius: CGFloat = 55
    /// Camera swipe: finger speed (pt/s) that gives full deflection.
    var swipeFullSpeed: CGFloat = 600
    /// Turbo: pressed and released for this long each, so 10 presses a second.
    static let turboHalfPeriod: TimeInterval = 0.05
    /// Clock of the last event or tick, for turbo and swipe decay.
    private(set) var now: TimeInterval = 0
    /// Deflection (0...1) below which the stick reads 0; the rest is rescaled so full deflection still gives 1.
    var deadZone: CGFloat = 0
    /// Left-stick deflection (0...1) that holds L3.
    var l3Threshold: CGFloat = 0.88
    /// Pushing the left stick to its edge holds L3; off, L3 comes only from an L3 button.
    var l3Push = true
    private static let l3Hysteresis: CGFloat = 0.04  // a trembling finger on the ring must not buzz the haptic
    /// Steering from tilting the phone (-1...1); replaces the left stick's X while set.
    var tilt: Double?
    /// Phone rotation that gives full lock.
    static let steeringLock = Double.pi / 4

    private(set) var left: Stick?
    private(set) var right: Stick?
    private(set) var l3 = false
    private var buttonTouches: [ObjectIdentifier: (placed: Profile.Placed, since: TimeInterval)] = [:]
    /// Toggle buttons currently held down by an earlier tap, with when they went down.
    private var latched: [UUID: TimeInterval] = [:]
    private var triggerTouches: [ObjectIdentifier: (control: Control, frame: CGRect, pull: Double)] = [:]

    /// Returns true when a control went down (caller fires the haptic).
    func began(_ touch: ObjectIdentifier, at p: CGPoint, time: TimeInterval = 0) -> Bool {
        now = time
        if let hit = layout.last(where: { contains(frame(of: $0), p) }) {
            let f = frame(of: hit)
            if hit.control.button == nil {
                triggerTouches[touch] = (hit.control, f, Self.pull(at: p, in: f))
            } else if hit.toggle {
                latched[hit.id] = latched[hit.id] == nil ? time : nil
            } else {
                buttonTouches[touch] = (hit, time)
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
            guard hypot(p.x - center.x, p.y - center.y) <= radius(setup) * 2 else { return false }
        }
        let stick = Stick(touch: touch, center: center, position: p, radius: radius(setup),
                          swipe: setup.mode == .swipe, time: time)
        if isLeft { left = stick } else { right = stick }
        return false
    }

    /// Returns true when the left stick crosses the L3 ring outward (caller fires the haptic).
    /// A touch stays bound to the stick/button/trigger it began on, wherever it moves (pointer capture).
    func moved(_ touch: ObjectIdentifier, to p: CGPoint, time: TimeInterval = 0) -> Bool {
        now = max(now, time)
        if var t = triggerTouches[touch] {
            t.pull = Self.pull(at: p, in: t.frame)
            triggerTouches[touch] = t
        }
        if right?.touch == touch { right = follow(right!, to: p, time, rightSetup) }
        guard let stick = left, stick.touch == touch else { return false }
        left = follow(stick, to: p, time, leftSetup)
        guard !stick.swipe, l3Push else { return false }
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

    /// Clock tick while `needsTicks`: turbo flips and a resting swipe finger lets the camera stop.
    func tick(_ time: TimeInterval) {
        now = max(now, time)
        // No movement for a couple of frames: the finger has stopped, so has the camera.
        if let s = left, s.swipe, now - s.time > 0.04 { left?.velocity = .zero }
        if let s = right, s.swipe, now - s.time > 0.04 { right?.velocity = .zero }
    }

    /// True while something changes with time alone (turbo buttons, a swipe finger).
    var needsTicks: Bool {
        left?.swipe == true || right?.swipe == true || buttonTouches.values.contains { $0.placed.turbo }
            || layout.contains { $0.turbo && latched[$0.id] != nil }
    }

    /// Current state; `seq` is filled in by the sender.
    var packet: GamepadPacket {
        var buttons = Buttons()
        let held = buttonTouches.values.map { ($0.placed, $0.since) }
            + layout.compactMap { p in latched[p.id].map { (p, $0) } }
        for (placed, since) in held where !placed.turbo || Int((now - since) / Self.turboHalfPeriod) % 2 == 0 {
            buttons.formUnion(placed.control.button ?? [])
        }
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

    /// A stick's size in points: its own, or the common one from Settings.
    func radius(_ setup: Profile.StickSetup) -> CGFloat {
        setup.radius.map { CGFloat($0) } ?? stickRadius
    }

    /// A stick's resting spot in points.
    func rest(_ setup: Profile.StickSetup) -> CGPoint {
        CGPoint(x: setup.center.x * size.width, y: setup.center.y * size.height)
    }

    /// Finger position clamped to the ring (drawn as is, without the dead zone).
    func knob(_ s: Stick) -> CGPoint {
        let dx = s.position.x - s.center.x, dy = s.position.y - s.center.y
        let length = hypot(dx, dy)
        guard length > s.radius else { return s.position }
        return CGPoint(x: s.center.x + dx / length * s.radius, y: s.center.y + dy / length * s.radius)
    }

    /// Steering from gravity in device coordinates: turning the phone clockwise (like a wheel) steers right.
    static func steering(gravityX gx: Double, gravityY gy: Double, landscapeRight: Bool) -> Double {
        // landscapeRight: the phone's top points left, so gravity is -x when level; landscapeLeft: +x.
        let angle = landscapeRight ? atan2(-gy, -gx) : atan2(gy, gx)
        return min(max(angle / steeringLock, -1), 1)
    }

    /// Dynamic: past the ring, the base is dragged along so it stays one radius behind the finger.
    /// Swipe: the finger's speed, smoothed over samples so 240 Hz jitter doesn't shake the camera.
    private func follow(_ s: Stick, to p: CGPoint, _ time: TimeInterval, _ setup: Profile.StickSetup) -> Stick {
        var s = s
        if s.swipe {
            let dt = time - s.time
            if dt > 0 {
                let v = CGVector(dx: (p.x - s.position.x) / dt, dy: (p.y - s.position.y) / dt)
                s.velocity = CGVector(dx: (s.velocity.dx + v.dx) / 2, dy: (s.velocity.dy + v.dy) / 2)
                s.time = time
            }
            s.position = p
            return s
        }
        s.position = p
        let dx = p.x - s.center.x, dy = p.y - s.center.y, length = hypot(dx, dy)
        if setup.mode == .dynamic, length > s.radius {
            s.center = CGPoint(x: p.x - dx / length * s.radius, y: p.y - dy / length * s.radius)
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
        min(hypot(s.position.x - s.center.x, s.position.y - s.center.y) / s.radius, 1)
    }

    /// -1...1 per axis, y up, clamped to the ring, with the radial dead zone applied.
    private func axes(_ s: Stick?) -> (x: Double, y: Double) {
        guard let s else { return (0, 0) }
        if s.swipe {
            let speed = hypot(s.velocity.dx, s.velocity.dy)
            guard speed > 0 else { return (0, 0) }
            // Slow swipes start at 12% so the game's own dead zone doesn't swallow fine aiming.
            let n = min(speed / swipeFullSpeed, 1)
            let out = n < 0.02 ? 0 : 0.12 + 0.88 * n
            return (Double(s.velocity.dx / speed * out), Double(-s.velocity.dy / speed * out))
        }
        let dx = s.position.x - s.center.x, dy = s.position.y - s.center.y
        let length = hypot(dx, dy)
        let d = min(length / s.radius, 1)
        guard length > 0, d > deadZone else { return (0, 0) }
        let scale = (d - deadZone) / (1 - deadZone) / length
        return (Double(dx * scale), Double(-dy * scale))
    }
}
