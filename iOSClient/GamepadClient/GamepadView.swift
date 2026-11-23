import SharedProtocol
import UIKit

/// Raw touch handling (no gesture recognizers) feeding TouchEngine, plus drawing.
final class GamepadView: UIView {
    let engine = TouchEngine()
    /// Called on every state change, before redraw.
    var onChange: ((GamepadPacket) -> Void)?

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var lastPacket = GamepadPacket()

    private static let labels: [GamepadPacket.Buttons: String] = [
        .dpadUp: "▲", .dpadDown: "▼", .dpadLeft: "◀", .dpadRight: "▶",
        .a: "A", .b: "B", .x: "X", .y: "Y",
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        contentMode = .redraw
        haptic.prepare()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        engine.size = bounds.size
        setNeedsDisplay()
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var buzz = false
        for t in touches where engine.began(ObjectIdentifier(t), at: t.location(in: self)) { buzz = true }
        commit(buzz)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var buzz = false
        for t in touches {
            // Coalesced samples (up to 240 Hz) so a fast flick can't skip over the L3 ring unnoticed.
            for sample in event?.coalescedTouches(for: t) ?? [t]
            where engine.moved(ObjectIdentifier(t), to: sample.location(in: self)) { buzz = true }
        }
        commit(buzz)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { engine.ended(ObjectIdentifier($0)) }
        commit(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { engine.ended(ObjectIdentifier($0)) }
        commit(false)
    }

    private func commit(_ buzz: Bool) {
        let packet = engine.packet
        if packet != lastPacket {
            lastPacket = packet
            onChange?(packet)  // network first, drawing after
            setNeedsDisplay()
        }
        if buzz {
            haptic.impactOccurred()
            haptic.prepare()
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let border = UIColor(white: 1, alpha: 0.22)
        let pressed = lastPacket.buttons

        for (button, frame) in engine.buttonCells() {
            if pressed.contains(button) {
                UIColor(white: 1, alpha: 0.28).setFill()
                ctx.fill(frame)
            }
            border.setStroke()
            ctx.stroke(frame.insetBy(dx: 0.5, dy: 0.5), width: 1)
            drawText(Self.labels[button] ?? "", at: CGPoint(x: frame.midX, y: frame.midY), size: 28,
                     alpha: pressed.contains(button) ? 1 : 0.6)
        }

        // Divider between the two stick zones.
        let split = bounds.height * TouchEngine.buttonZoneFraction
        border.setStroke()
        ctx.move(to: CGPoint(x: bounds.midX, y: split))
        ctx.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY))
        ctx.strokePath()

        let stickY = (split + bounds.maxY) / 2
        if engine.left == nil { drawText("LS", at: CGPoint(x: bounds.width / 4, y: stickY), size: 18, alpha: 0.25) }
        if engine.right == nil { drawText("RS", at: CGPoint(x: bounds.width * 3 / 4, y: stickY), size: 18, alpha: 0.25) }

        for (stick, sprint) in [(engine.left, engine.l3), (engine.right, false)] {
            guard let stick else { continue }
            let r = engine.stickRadius
            (sprint ? UIColor.systemOrange : UIColor(white: 1, alpha: 0.5)).setStroke()
            ctx.strokeEllipse(in: CGRect(x: stick.center.x - r, y: stick.center.y - r, width: r * 2, height: r * 2))
            let knob = engine.knob(stick)
            (sprint ? UIColor.systemOrange : UIColor.white).setFill()
            ctx.fillEllipse(in: CGRect(x: knob.x - 22, y: knob.y - 22, width: 44, height: 44))
        }
    }

    private func drawText(_ text: String, at center: CGPoint, size: CGFloat, alpha: CGFloat) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: UIColor(white: 1, alpha: alpha),
        ])
        let s = attributed.size()
        attributed.draw(at: CGPoint(x: center.x - s.width / 2, y: center.y - s.height / 2))
    }
}
