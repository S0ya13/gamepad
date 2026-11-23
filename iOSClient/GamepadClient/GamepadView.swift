import SharedProtocol
import UIKit

/// Raw touch handling (no gesture recognizers) feeding TouchEngine, plus drawing.
final class GamepadView: UIView {
    let engine = TouchEngine()
    /// Called on every state change, before redraw.
    var onChange: ((GamepadPacket) -> Void)?
    var haptics = true
    var theme = Profile.Theme.midnight {
        didSet {
            backgroundColor = theme.background
            setNeedsDisplay()
        }
    }

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var lastPacket = GamepadPacket()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = theme.background
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
        let pressed = lastPacket.buttons

        if let tilt = engine.tilt {
            // Steering gauge where the left stick rests.
            let rest = engine.rest(engine.leftSetup)
            let gauge = CGRect(x: rest.x - 60, y: rest.y, width: 120, height: 2)
            UIColor(white: 1, alpha: 0.22).setFill()
            ctx.fill(gauge)
            UIColor.white.setFill()
            ctx.fillEllipse(in: CGRect(x: gauge.midX + tilt * 60 - 6, y: rest.y - 5, width: 12, height: 12))
            drawText("TILT", at: CGPoint(x: gauge.midX, y: rest.y - 22), size: 14, alpha: 0.25)
        } else if engine.left == nil {
            drawStick(center: engine.rest(engine.leftSetup), knob: engine.rest(engine.leftSetup), active: false,
                      color: theme.stick, in: ctx)
        }
        if engine.right == nil {
            drawStick(center: engine.rest(engine.rightSetup), knob: engine.rest(engine.rightSetup), active: false,
                      color: theme.stick, in: ctx)
        }

        for placed in engine.layout {
            let frame = engine.frame(of: placed)
            let color = placed.uiColor(theme)
            // 0 idle ... 1 fully down; triggers are analog.
            let level = placed.control.button.map { pressed.contains($0) ? 1 : 0 }
                ?? CGFloat(placed.control == .lt ? lastPacket.lt : lastPacket.rt) / 255
            let down = level > 0
            // A pressed button sinks a little; gaps between neighbours keep cells readable.
            let sink: CGFloat = down && placed.control.button != nil ? 4 : 2.5
            let path = Self.path(placed.shape, in: frame.insetBy(dx: sink, dy: sink))

            ctx.saveGState()
            if down { ctx.setShadow(offset: .zero, blur: 18, color: color.withAlphaComponent(0.9).cgColor) }
            color.withAlphaComponent(down ? 0.18 : 0.08).setFill()
            path.fill()
            ctx.restoreGState()

            ctx.saveGState()
            path.addClip()
            // Pressed buttons fill whole; a trigger fills from the top as deep as it is pulled.
            color.withAlphaComponent(0.45).setFill()
            ctx.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * level))
            ctx.restoreGState()

            color.withAlphaComponent(down ? 1 : 0.45).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            let title = placed.title
            let size = min(28, frame.height * 0.4, frame.width / CGFloat(max(title.count, 2)) * 1.2)
            drawText(title, at: CGPoint(x: frame.midX, y: frame.midY), size: size, alpha: down ? 1 : 0.85,
                     color: down ? .white : color)
        }

        for (stick, sprint) in [(engine.left, engine.l3), (engine.right, false)] {
            guard let stick else { continue }
            drawStick(center: stick.center, knob: engine.knob(stick), active: true,
                      color: sprint ? .systemOrange : theme.stick, in: ctx)
        }
    }

    /// Base and knob; at rest they are drawn faint where the stick lives.
    private func drawStick(center: CGPoint, knob: CGPoint, active: Bool, color: UIColor, in ctx: CGContext) {
        let r = engine.stickRadius
        let base = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        color.withAlphaComponent(active ? 0.08 : 0.03).setFill()
        ctx.fillEllipse(in: base)
        color.withAlphaComponent(active ? 0.45 : 0.16).setStroke()
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: base.insetBy(dx: 1, dy: 1))

        let k = CGRect(x: knob.x - 26, y: knob.y - 26, width: 52, height: 52)
        ctx.saveGState()
        if active { ctx.setShadow(offset: .zero, blur: 16, color: color.withAlphaComponent(0.6).cgColor) }
        color.withAlphaComponent(active ? 0.92 : 0.2).setFill()
        ctx.fillEllipse(in: k)
        ctx.restoreGState()
        // Grip ring on the knob.
        UIColor(white: 0, alpha: active ? 0.18 : 0.3).setStroke()
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: k.insetBy(dx: 8, dy: 8))
    }

    /// The control's outline; the whole rectangle still takes touches, so a circle is easy to hit.
    static func path(_ shape: Profile.Placed.Shape, in frame: CGRect) -> UIBezierPath {
        let inset = frame
        switch shape {
        case .square: return UIBezierPath(roundedRect: inset, cornerRadius: 6)
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
