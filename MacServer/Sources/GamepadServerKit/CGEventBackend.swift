import ApplicationServices
import Carbon.HIToolbox
import Foundation
import SharedProtocol

/// Keyboard & mouse emulation. What each control presses comes from the phone's game profile (`KeyMap`).
public final class CGEventBackend: InputBackend {
    enum Output: Hashable {
        case key(Int)
        case mouse(CGMouseButton)
    }

    /// `KeyMap.keyNames` → what to press.
    static let outputs: [String: Output] = {
        var table: [String: Output] = [
            "Mouse Left": .mouse(.left), "Mouse Right": .mouse(.right), "Mouse Middle": .mouse(.center),
            "Space": .key(kVK_Space), "Return": .key(kVK_Return), "Tab": .key(kVK_Tab), "Escape": .key(kVK_Escape),
            "Delete": .key(kVK_Delete), "Shift": .key(kVK_Shift), "Control": .key(kVK_Control),
            "Option": .key(kVK_Option), "Command": .key(kVK_Command),
            "Up": .key(kVK_UpArrow), "Down": .key(kVK_DownArrow), "Left": .key(kVK_LeftArrow), "Right": .key(kVK_RightArrow),
        ]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                       kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                       kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                       kVK_ANSI_Y, kVK_ANSI_Z]
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7,
                      kVK_ANSI_8, kVK_ANSI_9]
        for (name, code) in zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", letters + digits) { table[String(name)] = .key(code) }
        return table
    }()

    private static let modifiers: [(Int, CGEventFlags)] = [
        (kVK_Shift, .maskShift), (kVK_Control, .maskControl), (kVK_Option, .maskAlternate), (kVK_Command, .maskCommand),
    ]
    private static let moveThreshold = 0.3     // stick deflection per axis that presses a direction key
    private static let triggerThreshold: UInt8 = 64  // a quarter pull presses the trigger's key
    private static let lookDeadzone = 0.05
    private static let tickHz = 120.0

    private let source = CGEventSource(stateID: .hidSystemState)
    /// Mouse pixels per 120 Hz tick at full stick deflection.
    public var pixelsPerTick: Double
    private var map = SharedProtocol.KeyMap.standard
    private var pressed = Set<Output>()
    private var look = (x: 0.0, y: 0.0)
    private var remainder = (x: 0.0, y: 0.0)
    private let timer = DispatchSource.makeTimerSource(queue: .main)

    /// CGEvent posts are silently dropped without the permission; check `hasAccessibility` first.
    public init(sensitivity: Double) {
        pixelsPerTick = sensitivity
        timer.schedule(deadline: .now(), repeating: 1 / Self.tickHz, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.moveMouse() }
        timer.resume()
    }

    deinit { timer.cancel() }

    /// `prompt` shows the system dialog that leads to Privacy & Security → Device Control and Data Access (Accessibility before macOS 27).
    public static func hasAccessibility(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary)
    }

    public func use(_ keys: SharedProtocol.KeyMap) {
        reset()  // release what the old mapping held
        map = keys
    }

    public func apply(_ p: GamepadPacket) {
        var want = Set<Output>()
        look = (0, 0)
        stick(GamepadPacket.unit(p.lx), GamepadPacket.unit(p.ly), map.leftStick, into: &want)
        stick(GamepadPacket.unit(p.rx), GamepadPacket.unit(p.ry), map.rightStick, into: &want)
        for control in Control.allCases {
            let down = control.button.map { p.buttons.contains($0) }
                ?? ((control == .lt ? p.lt : p.rt) >= Self.triggerThreshold)
            if down, let output = map.keys[control].flatMap({ Self.outputs[$0] }) { want.insert(output) }
        }
        set(want)
    }

    public func reset() {
        set([])
        look = (0, 0)
        remainder = (0, 0)
    }

    private func stick(_ x: Double, _ y: Double, _ mode: SharedProtocol.KeyMap.Stick, into want: inout Set<Output>) {
        let keys: [Int]
        switch mode {
        case .none: return
        case .mouse:
            look.x += curve(x)
            look.y += curve(y)
            return
        case .wasd: keys = [kVK_ANSI_W, kVK_ANSI_S, kVK_ANSI_A, kVK_ANSI_D]
        case .arrows: keys = [kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow]
        }
        if y > Self.moveThreshold { want.insert(.key(keys[0])) }
        if y < -Self.moveThreshold { want.insert(.key(keys[1])) }
        if x < -Self.moveThreshold { want.insert(.key(keys[2])) }
        if x > Self.moveThreshold { want.insert(.key(keys[3])) }
    }

    private func set(_ want: Set<Output>) {
        let released = pressed.subtracting(want), added = want.subtracting(pressed)
        for output in released { post(output, down: false) }
        pressed = want  // before posting, so modifier flags are already right for keys pressed together with them
        // Modifiers first: Shift + W in one packet must reach the game as Shift-W.
        for output in added.sorted(by: { isModifier($0) && !isModifier($1) }) { post(output, down: true) }
    }

    private func isModifier(_ output: Output) -> Bool {
        if case .key(let code) = output { return Self.modifiers.contains { $0.0 == code } }
        return false
    }

    private func post(_ output: Output, down: Bool) {
        switch output {
        case .key(let code):
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { return }
            e.flags = CGEventFlags(Self.modifiers.filter { pressed.contains(.key($0.0)) }.map(\.1))
            e.post(tap: .cghidEventTap)
        case .mouse(let button):
            let type: CGEventType = switch button {
            case .left: down ? .leftMouseDown : .leftMouseUp
            case .right: down ? .rightMouseDown : .rightMouseUp
            default: down ? .otherMouseDown : .otherMouseUp
            }
            guard let at = CGEvent(source: nil)?.location,
                  let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: button)
            else { return }
            e.post(tap: .cghidEventTap)
        }
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
        // While a mouse button is held, games expect drags, not plain moves.
        let (type, button): (CGEventType, CGMouseButton) =
            pressed.contains(.mouse(.left)) ? (.leftMouseDragged, .left)
            : pressed.contains(.mouse(.right)) ? (.rightMouseDragged, .right)
            : pressed.contains(.mouse(.center)) ? (.otherMouseDragged, .center)
            : (.mouseMoved, .left)
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: button)
        else { return }
        // Games with a captured cursor read these deltas, not the position.
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e.post(tap: .cghidEventTap)
    }
}
