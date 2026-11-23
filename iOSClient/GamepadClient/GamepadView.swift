import SharedProtocol
import UIKit

/// Raw touch handling (no gesture recognizers) feeding TouchEngine, plus drawing.
final class GamepadView: UIView {
    let engine = TouchEngine()
    /// Called on every state change, before redraw.
    var onChange: ((GamepadPacket) -> Void)?
    var haptics = true

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var lastPacket = GamepadPacket()

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

    /// Steering from the motion sensor; nil turns tilt off.
    func setTilt(_ value: Double?) {
        engine.tilt = value
        if value == nil { setNeedsDisplay() }
        commit(false)
    }

    private func commit(_ buzz: Bool) {
        let packet = engine.packet
        if packet != lastPacket {
            lastPacket = packet
            onChange?(packet)  // network first, drawing after
            setNeedsDisplay()
        }
        if buzz && haptics {
            haptic.impactOccurred()
            haptic.prepare()
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let border = UIColor(white: 1, alpha: 0.22)
        let pressed = lastPacket.buttons

        // Divider between the two stick halves; controls drawn on top hide it.
        border.setStroke()
        ctx.move(to: CGPoint(x: bounds.midX, y: 0))
        ctx.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY))
        ctx.strokePath()

        if let tilt = engine.tilt {
            // Steering gauge where the left stick rests.
            let rest = engine.rest(engine.leftSetup)
            let gauge = CGRect(x: rest.x - 60, y: rest.y, width: 120, height: 2)
            border.setFill()
            ctx.fill(gauge)
            UIColor.white.setFill()
            ctx.fillEllipse(in: CGRect(x: gauge.midX + tilt * 60 - 6, y: rest.y - 5, width: 12, height: 12))
            drawText("TILT", at: CGPoint(x: gauge.midX, y: rest.y - 22), size: 14, alpha: 0.25)
        } else if engine.left == nil {
            drawStick(center: engine.rest(engine.leftSetup), knob: engine.rest(engine.leftSetup), alpha: 0.25, in: ctx)
        }
        if engine.right == nil {
            drawStick(center: engine.rest(engine.rightSetup), knob: engine.rest(engine.rightSetup), alpha: 0.25, in: ctx)
        }

        for placed in engine.layout {
            let frame = engine.frame(of: placed)
            let path = Self.path(placed.shape, in: frame)
            let color = placed.uiColor
            UIColor.black.setFill()
            path.fill()
            var down = false
            ctx.saveGState()
            path.addClip()
            if let button = placed.control.button {
                down = pressed.contains(button)
                if down {
                    color.withAlphaComponent(0.35).setFill()
                    ctx.fill(frame)
                }
            } else {
                // Trigger: filled from the top as deep as it is pulled.
                let pull = CGFloat(placed.control == .lt ? lastPacket.lt : lastPacket.rt) / 255
                down = pull > 0
                color.withAlphaComponent(0.35).setFill()
                ctx.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * pull))
            }
            ctx.restoreGState()
            color.withAlphaComponent(placed.color == nil ? 0.22 : 0.6).setStroke()
            path.lineWidth = placed.color == nil ? 1 : 2
            path.stroke()
            let title = placed.title
            let size = min(28, frame.height * 0.4, frame.width / CGFloat(max(title.count, 2)) * 1.2)
            drawText(title, at: CGPoint(x: frame.midX, y: frame.midY), size: size, alpha: down ? 1 : 0.6, color: color)
        }

        for (stick, sprint) in [(engine.left, engine.l3), (engine.right, false)] {
            guard let stick else { continue }
            drawStick(center: stick.center, knob: engine.knob(stick), alpha: 1,
                      color: sprint ? .systemOrange : .white, in: ctx)
        }
    }

    /// Ring and knob; at rest they are drawn faint where the stick lives.
    private func drawStick(center: CGPoint, knob: CGPoint, alpha: CGFloat, color: UIColor = .white, in ctx: CGContext) {
        let r = engine.stickRadius
        color.withAlphaComponent(alpha * 0.5).setStroke()
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        color.withAlphaComponent(alpha).setFill()
        ctx.fillEllipse(in: CGRect(x: knob.x - 22, y: knob.y - 22, width: 44, height: 44))
    }

    /// The control's outline; the whole rectangle still takes touches, so a circle is easy to hit.
    static func path(_ shape: Profile.Placed.Shape, in frame: CGRect) -> UIBezierPath {
        let inset = frame.insetBy(dx: 1, dy: 1)
        switch shape {
        case .square: return UIBezierPath(rect: inset)
        case .rounded: return UIBezierPath(roundedRect: inset, cornerRadius: min(inset.width, inset.height) * 0.25)
        case .circle:
            let d = min(inset.width, inset.height)
            return UIBezierPath(ovalIn: CGRect(x: inset.midX - d / 2, y: inset.midY - d / 2, width: d, height: d))
        }
    }

    private func drawText(_ text: String, at center: CGPoint, size: CGFloat, alpha: CGFloat, color: UIColor = .white) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color.withAlphaComponent(alpha),
        ])
        let s = attributed.size()
        attributed.draw(at: CGPoint(x: center.x - s.width / 2, y: center.y - s.height / 2))
    }
}
