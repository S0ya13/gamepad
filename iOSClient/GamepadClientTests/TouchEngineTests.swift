import SharedProtocol
import XCTest
@testable import GamepadClient

final class TouchEngineTests: XCTestCase {
    // 800×400 landscape: buttons y < 160 (rows split at 80), sticks below; halves split at x = 400.
    private var engine: TouchEngine!
    private let a = NSObject(), b = NSObject(), c = NSObject(), d = NSObject()

    override func setUp() {
        engine = TouchEngine()
        engine.size = CGSize(width: 800, height: 400)
        engine.stickRadius = 100
    }

    private func id(_ o: NSObject) -> ObjectIdentifier { ObjectIdentifier(o) }

    func testButtonGridHitTesting() {
        let cases: [(CGPoint, GamepadPacket.Buttons)] = [
            (CGPoint(x: 10, y: 10), .dpadLeft), (CGPoint(x: 390, y: 10), .dpadUp),
            (CGPoint(x: 10, y: 150), .dpadDown), (CGPoint(x: 390, y: 150), .dpadRight),
            (CGPoint(x: 410, y: 10), .x), (CGPoint(x: 790, y: 10), .y),
            (CGPoint(x: 410, y: 150), .a), (CGPoint(x: 800, y: 159), .b),
        ]
        for (point, expected) in cases {
            let t = NSObject()
            XCTAssertTrue(engine.began(id(t), at: point), "\(point)")
            XCTAssertEqual(engine.packet.buttons, expected, "\(point)")
            engine.ended(id(t))
        }
        XCTAssertEqual(engine.packet, GamepadPacket())
    }

    func testStickCaptureSurvivesMovingIntoButtonZone() {
        XCTAssertFalse(engine.began(id(a), at: CGPoint(x: 200, y: 300)))
        _ = engine.moved(id(a), to: CGPoint(x: 200, y: 0))  // dragged up into the D-pad area
        let p = engine.packet
        XCTAssertEqual(p.buttons, .l3)  // full deflection, but no D-pad button
        XCTAssertEqual(p.ly, 32767)
        XCTAssertEqual(p.lx, 0)
        engine.ended(id(a))
        XCTAssertEqual(engine.packet, GamepadPacket())
    }

    func testAxesAreClampedAndYIsUp() {
        _ = engine.began(id(a), at: CGPoint(x: 600, y: 300))
        _ = engine.moved(id(a), to: CGPoint(x: 650, y: 350))  // right-down, inside the ring
        XCTAssertEqual(GamepadPacket.unit(engine.packet.rx), 0.5, accuracy: 1e-3)
        XCTAssertEqual(GamepadPacket.unit(engine.packet.ry), -0.5, accuracy: 1e-3)
        _ = engine.moved(id(a), to: CGPoint(x: 1000, y: 300))  // way past the ring
        XCTAssertEqual(engine.packet.rx, 32767)
        XCTAssertEqual(engine.packet.ry, 0)
        XCTAssertFalse(engine.packet.buttons.contains(.l3), "right stick never sets L3")
    }

    func testL3ThresholdHysteresisAndSingleHaptic() {
        _ = engine.began(id(a), at: CGPoint(x: 200, y: 300))
        XCTAssertFalse(engine.moved(id(a), to: CGPoint(x: 287, y: 300)))  // 0.87
        XCTAssertFalse(engine.l3)
        XCTAssertTrue(engine.moved(id(a), to: CGPoint(x: 289, y: 300)))   // 0.89 -> on, haptic
        XCTAssertFalse(engine.moved(id(a), to: CGPoint(x: 300, y: 300)))  // still on, no second haptic
        XCTAssertFalse(engine.moved(id(a), to: CGPoint(x: 286, y: 300)))  // 0.86: kept by hysteresis
        XCTAssertTrue(engine.l3)
        XCTAssertFalse(engine.moved(id(a), to: CGPoint(x: 280, y: 300)))  // 0.80 -> off
        XCTAssertFalse(engine.l3)
        XCTAssertTrue(engine.moved(id(a), to: CGPoint(x: 295, y: 300)))   // on again
        engine.ended(id(a))
        XCTAssertFalse(engine.l3)
    }

    func testFullMultitouch() {
        _ = engine.began(id(a), at: CGPoint(x: 100, y: 300))  // left stick
        _ = engine.began(id(b), at: CGPoint(x: 700, y: 300))  // right stick
        _ = engine.began(id(c), at: CGPoint(x: 410, y: 150))  // A
        _ = engine.began(id(d), at: CGPoint(x: 10, y: 10))    // D-pad left
        _ = engine.moved(id(a), to: CGPoint(x: 50, y: 300))
        _ = engine.moved(id(b), to: CGPoint(x: 700, y: 250))
        let p = engine.packet
        XCTAssertEqual(p.buttons, [.a, .dpadLeft])
        XCTAssertEqual(GamepadPacket.unit(p.lx), -0.5, accuracy: 1e-3)
        XCTAssertEqual(GamepadPacket.unit(p.ry), 0.5, accuracy: 1e-3)
        engine.ended(id(c))
        XCTAssertEqual(engine.packet.buttons, .dpadLeft)
    }

    func testSecondFingerInActiveStickZoneIsIgnored() {
        _ = engine.began(id(a), at: CGPoint(x: 100, y: 300))
        _ = engine.began(id(b), at: CGPoint(x: 300, y: 300))
        _ = engine.moved(id(b), to: CGPoint(x: 400, y: 300))
        XCTAssertEqual(engine.packet.lx, 0)
        engine.ended(id(b))
        XCTAssertNotNil(engine.left)
    }
}
