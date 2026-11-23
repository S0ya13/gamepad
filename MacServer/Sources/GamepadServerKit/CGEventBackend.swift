import ApplicationServices
import Carbon.HIToolbox
import Foundation
import SharedProtocol

public final class CGEventBackend: InputBackend {
    /// Button -> key. Edit this table to remap.
    static let buttonKeys: [(GamepadPacket.Buttons, Int)] = [
        (.a, kVK_Space),
        (.b, kVK_ANSI_F),
        (.x, kVK_ANSI_R),
        (.y, kVK_ANSI_E),
        (.dpadUp, kVK_ANSI_1),
        (.dpadDown, kVK_ANSI_2),
        (.dpadLeft, kVK_ANSI_3),
        (.dpadRight, kVK_ANSI_4),
        (.l3, kVK_Shift),
    ]

    private static let moveThreshold = 0.3   // left stick deflection per axis that presses W/A/S/D
    private static let lookDeadzone = 0.05
    private static let tickHz = 120.0

    private let source = CGEventSource(stateID: .hidSystemState)
    /// Mouse pixels per 120 Hz tick at full right-stick deflection.
    public var pixelsPerTick: Double
    private var pressed = Set<Int>()
    private var look = (x: 0.0, y: 0.0)
    private var remainder = (x: 0.0, y: 0.0)
    private let timer = DispatchSource.makeTimerSource(queue: .main)

    /// CGEvent posts are silently dropped without Accessibility permission; check `hasAccessibility` first.
    public init(sensitivity: Double) {
        pixelsPerTick = sensitivity
        timer.schedule(deadline: .now(), repeating: 1 / Self.tickHz, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.moveMouse() }
        timer.resume()
    }

    deinit { timer.cancel() }

    /// `prompt` shows the system dialog that leads to Privacy & Security → Accessibility.
    public static func hasAccessibility(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary)
    }

    public func apply(_ p: GamepadPacket) {
        let lx = GamepadPacket.unit(p.lx), ly = GamepadPacket.unit(p.ly)
        var want = Set<Int>()
        if ly > Self.moveThreshold { want.insert(kVK_ANSI_W) }
        if ly < -Self.moveThreshold { want.insert(kVK_ANSI_S) }
        if lx < -Self.moveThreshold { want.insert(kVK_ANSI_A) }
        if lx > Self.moveThreshold { want.insert(kVK_ANSI_D) }
        for (button, key) in Self.buttonKeys where p.buttons.contains(button) { want.insert(key) }
        setKeys(want)
        look = (curve(GamepadPacket.unit(p.rx)), curve(GamepadPacket.unit(p.ry)))
    }

    public func reset() {
        setKeys([])
        look = (0, 0)
        remainder = (0, 0)
    }

    private func setKeys(_ want: Set<Int>) {
        for key in pressed.subtracting(want) { post(key, down: false) }
        let added = want.subtracting(pressed)
        pressed = want  // before posting, so the Shift flag is already right for keys pressed together with it
        if added.contains(kVK_Shift) { post(kVK_Shift, down: true) }
        for key in added where key != kVK_Shift { post(key, down: true) }
    }

    private func post(_ key: Int, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { return }
        e.flags = pressed.contains(kVK_Shift) ? .maskShift : []
        e.post(tap: .cghidEventTap)
    }

    /// Deadzone + square response: fine aim near center, full speed at the edge.
    private func curve(_ v: Double) -> Double {
        abs(v) < Self.lookDeadzone ? 0 : v * abs(v)
    }

    private func moveMouse() {
        guard look != (0, 0) else { return }
        // Keep sub-pixel remainder so slow aim still moves.
        remainder.x += look.x * pixelsPerTick
        remainder.y -= look.y * pixelsPerTick  // stick up = screen up = -y
        let dx = remainder.x.rounded(.towardZero), dy = remainder.y.rounded(.towardZero)
        remainder.x -= dx
        remainder.y -= dy
        guard dx != 0 || dy != 0, let current = CGEvent(source: nil)?.location else { return }

        // shortcut: clamps to the main display only; upgrade when playing on an external monitor.
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let target = CGPoint(x: min(max(current.x + dx, bounds.minX), bounds.maxX - 1),
                             y: min(max(current.y + dy, bounds.minY), bounds.maxY - 1))
        guard let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                              mouseCursorPosition: target, mouseButton: .left) else { return }
        // Games with a captured cursor read these deltas, not the position.
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e.post(tap: .cghidEventTap)
    }
}
