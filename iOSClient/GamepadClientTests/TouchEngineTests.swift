import SharedProtocol
import XCTest
import UIKit
@testable import GamepadClient

final class TouchEngineTests: XCTestCase {
    // 800×400 landscape: buttons y < 160 (rows split at 80), sticks below; halves split at x = 400.
    private var engine: TouchEngine!
    private let a = NSObject(), b = NSObject(), c = NSObject(), d = NSObject()

    override func setUp() {
        engine = TouchEngine()
        engine.size = CGSize(width: 800, height: 400)
        engine.stickRadius = 100
        engine.layout = Profile.standard.controls
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

    func testDeadZoneRescalesToFullRange() {
        engine.deadZone = 0.2
        _ = engine.began(id(a), at: CGPoint(x: 600, y: 300))
        _ = engine.moved(id(a), to: CGPoint(x: 615, y: 300))  // 0.15: inside
        XCTAssertEqual(engine.packet.rx, 0)
        _ = engine.moved(id(a), to: CGPoint(x: 660, y: 300))  // 0.6 -> (0.6 - 0.2) / 0.8
        XCTAssertEqual(GamepadPacket.unit(engine.packet.rx), 0.5, accuracy: 1e-3)
        _ = engine.moved(id(a), to: CGPoint(x: 600, y: 200))  // full up
        XCTAssertEqual(engine.packet.ry, 32767)
        XCTAssertEqual(engine.knob(engine.right!), CGPoint(x: 600, y: 200), "knob is drawn without the dead zone")
    }

    func testCustomL3Threshold() {
        engine.l3Threshold = 0.6
        _ = engine.began(id(a), at: CGPoint(x: 200, y: 300))
        XCTAssertFalse(engine.moved(id(a), to: CGPoint(x: 259, y: 300)))
        XCTAssertTrue(engine.moved(id(a), to: CGPoint(x: 261, y: 300)))
        XCTAssertFalse(engine.moved(id(a), to: CGPoint(x: 257, y: 300)))  // 0.57: kept by hysteresis
        XCTAssertTrue(engine.l3)
    }

    func testTriggerIsAnalogByFingerDepthAndKeepsCapture() {
        // A trigger 200 pt tall on the right; the standard grid is gone.
        engine.layout = [Profile.Placed(control: .rt, frame: CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5))]
        XCTAssertTrue(engine.began(id(a), at: CGPoint(x: 700, y: 200)))   // top edge: a quarter
        XCTAssertEqual(engine.packet.rt, GamepadPacket.trigger(0.25))
        _ = engine.moved(id(a), to: CGPoint(x: 700, y: 300))              // halfway down
        XCTAssertEqual(engine.packet.rt, GamepadPacket.trigger(0.625))
        _ = engine.moved(id(a), to: CGPoint(x: 100, y: 900))              // dragged far away: still the trigger, full
        XCTAssertEqual(engine.packet.rt, 255)
        XCTAssertEqual(engine.packet.lt, 0)
        XCTAssertNil(engine.left, "a trigger finger never becomes a stick")
        engine.ended(id(a))
        XCTAssertEqual(engine.packet, GamepadPacket())
    }

    func testNewButtonsAndTopmostControlWins() {
        engine.layout = [
            Profile.Placed(control: .lb, frame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            Profile.Placed(control: .start, frame: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)),
        ]
        _ = engine.began(id(a), at: CGPoint(x: 50, y: 50))
        _ = engine.began(id(b), at: CGPoint(x: 300, y: 150))  // overlap: Start is on top
        XCTAssertEqual(engine.packet.buttons, [.lb, .start])
        XCTAssertFalse(engine.began(id(c), at: CGPoint(x: 100, y: 300)), "empty space is a stick")
        XCTAssertNotNil(engine.left)
    }

    func testTiltReplacesLeftStickX() {
        _ = engine.began(id(a), at: CGPoint(x: 200, y: 300))
        _ = engine.moved(id(a), to: CGPoint(x: 150, y: 250))  // left and up
        engine.tilt = 0.5
        XCTAssertEqual(GamepadPacket.unit(engine.packet.lx), 0.5, accuracy: 1e-3)
        XCTAssertEqual(GamepadPacket.unit(engine.packet.ly), 0.5, accuracy: 1e-3, "Y still from the stick")
    }

    func testSteeringFromGravity() {
        let s = Double.pi / 8, c = cos(s), sn = sin(s)  // 22.5° = half lock
        // landscapeRight: level phone has gravity -x; turned clockwise it rotates toward -y.
        XCTAssertEqual(TouchEngine.steering(gravityX: -1, gravityY: 0, landscapeRight: true), 0, accuracy: 1e-9)
        XCTAssertEqual(TouchEngine.steering(gravityX: -c, gravityY: -sn, landscapeRight: true), 0.5, accuracy: 1e-9)
        XCTAssertEqual(TouchEngine.steering(gravityX: -c, gravityY: sn, landscapeRight: true), -0.5, accuracy: 1e-9)
        // landscapeLeft: level is +x; clockwise rotates toward +y.
        XCTAssertEqual(TouchEngine.steering(gravityX: c, gravityY: sn, landscapeRight: false), 0.5, accuracy: 1e-9)
        // Upright portrait (turned a full 90° clockwise from landscapeRight): clamped to full lock.
        XCTAssertEqual(TouchEngine.steering(gravityX: 0, gravityY: -1, landscapeRight: true), 1)
    }

    func testSecondFingerInActiveStickZoneIsIgnored() {
        _ = engine.began(id(a), at: CGPoint(x: 100, y: 300))
        _ = engine.began(id(b), at: CGPoint(x: 300, y: 300))
        _ = engine.moved(id(b), to: CGPoint(x: 400, y: 300))
        XCTAssertEqual(engine.packet.lx, 0)
        engine.ended(id(b))
        XCTAssertNotNil(engine.left)
    }

    func testFixedStickCentersOnItsSpotAndIgnoresFarTouches() {
        engine.leftSetup = Profile.StickSetup(mode: .fixed, center: CGPoint(x: 0.25, y: 0.75))  // (200, 300)
        XCTAssertFalse(engine.began(id(a), at: CGPoint(x: 0, y: 399)), "more than 2 radii away")
        XCTAssertNil(engine.left)
        _ = engine.began(id(b), at: CGPoint(x: 250, y: 300))  // lands half a radius right of the base
        XCTAssertEqual(engine.left?.center, CGPoint(x: 200, y: 300))
        XCTAssertEqual(GamepadPacket.unit(engine.packet.lx), 0.5, accuracy: 1e-3)
    }

    func testDynamicStickBaseFollowsFinger() {
        engine.rightSetup.mode = .dynamic
        _ = engine.began(id(a), at: CGPoint(x: 500, y: 300))
        _ = engine.moved(id(a), to: CGPoint(x: 750, y: 300))  // 2.5 radii right
        XCTAssertEqual(engine.right?.center, CGPoint(x: 650, y: 300), "dragged to one radius behind")
        XCTAssertEqual(engine.packet.rx, 32767)
        _ = engine.moved(id(a), to: CGPoint(x: 550, y: 300))  // one diameter back: already full left
        XCTAssertEqual(engine.packet.rx, -32767)
        XCTAssertEqual(engine.right?.center, CGPoint(x: 650, y: 300), "inside the ring the base stays")

        engine.rightSetup.mode = .floating
        engine.ended(id(a))
        _ = engine.began(id(a), at: CGPoint(x: 500, y: 300))
        _ = engine.moved(id(a), to: CGPoint(x: 750, y: 300))
        XCTAssertEqual(engine.right?.center, CGPoint(x: 500, y: 300), "floating base stays put")
    }

    func testToggleButtonLatchesUntilTappedAgain() {
        engine.layout[6].toggle = true  // A
        _ = engine.began(id(a), at: CGPoint(x: 410, y: 150))
        engine.ended(id(a))
        XCTAssertEqual(engine.packet.buttons, .a, "held after the finger lifts")
        XCTAssertTrue(engine.began(id(b), at: CGPoint(x: 410, y: 150)))
        XCTAssertEqual(engine.packet.buttons, [])
        engine.ended(id(b))
        _ = engine.began(id(a), at: CGPoint(x: 410, y: 150))
        engine.layout[6].toggle = false  // turning the option off lets go
        XCTAssertEqual(engine.packet.buttons, [])
    }

    func testProfileFromOlderBuildKeepsLayoutAndGetsDefaults() throws {
        let old = #"""
        {"id":"6A22C07A-905B-4543-AE09-534A7749B4A2","name":"Mine","tilt":true,"keys":\#(String(data: try JSONEncoder().encode(KeyMap.standard), encoding: .utf8)!),
         "controls":[{"id":"7A22C07A-905B-4543-AE09-534A7749B4A2","control":"lb","frame":[[0.1,0.2],[0.3,0.4]]}]}
        """#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertEqual(p.name, "Mine")
        XCTAssertTrue(p.tilt)
        XCTAssertEqual(p.controls.first?.frame, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(p.controls.first?.shape, .square)
        XCTAssertNil(p.controls.first?.label)
        XCTAssertEqual(p.leftStick, .left)
        XCTAssertEqual(p.rightStick.mode, .dynamic, "sticks follow the finger by default")
    }

    func testHexColorRoundTrip() {
        XCTAssertEqual(UIColor(hex: "#FF8000")?.hex, "#FF8000")
        XCTAssertNil(UIColor(hex: "red"))

        var a = Profile.Placed(control: .a, frame: .zero)
        XCTAssertEqual(a.uiColor(.mono).hex, "#FFFFFF", "Mono leaves face buttons plain")
        XCTAssertEqual(a.uiColor(.neon).hex, "#39FF88")
        XCTAssertEqual(Profile.Placed(control: .lb, frame: .zero).uiColor(.neon).hex, "#3DF5FF", "other buttons take the accent")
        a.color = "#123456"
        XCTAssertEqual(a.uiColor(.neon).hex, "#123456", "the button's own colour wins")
    }

    func testCameraSwipeReadsSpeedAndStopsWhenFingerRests() {
        engine.rightSetup.mode = .swipe
        engine.swipeFullSpeed = 600
        _ = engine.began(id(a), at: CGPoint(x: 600, y: 300), time: 1)
        XCTAssertEqual(engine.packet.rx, 0, "a touch alone doesn't turn the camera")
        _ = engine.moved(id(a), to: CGPoint(x: 606, y: 300), time: 1.01)  // 600 pt/s, smoothed to half
        XCTAssertEqual(GamepadPacket.unit(engine.packet.rx), 0.12 + 0.88 * 0.5, accuracy: 1e-3)
        _ = engine.moved(id(a), to: CGPoint(x: 612, y: 300), time: 1.02)  // 0.75 of full speed
        XCTAssertEqual(GamepadPacket.unit(engine.packet.rx), 0.12 + 0.88 * 0.75, accuracy: 1e-3)
        XCTAssertEqual(engine.packet.ry, 0)
        XCTAssertTrue(engine.needsTicks)
        engine.tick(1.05)
        XCTAssertNotEqual(engine.packet.rx, 0, "30 ms between samples is still moving")
        engine.tick(1.07)
        XCTAssertEqual(engine.packet.rx, 0, "finger stopped: camera stops")
        _ = engine.moved(id(a), to: CGPoint(x: 612, y: 290), time: 1.08)
        _ = engine.moved(id(a), to: CGPoint(x: 612, y: 260), time: 1.09)  // up, far past full speed
        XCTAssertEqual(engine.packet.ry, 32767)
        engine.ended(id(a))
        XCTAssertFalse(engine.needsTicks)
    }

    func testTurboPulsesWhileHeld() {
        engine.layout[6].turbo = true  // A
        _ = engine.began(id(a), at: CGPoint(x: 410, y: 150), time: 10)
        XCTAssertTrue(engine.needsTicks)
        XCTAssertEqual(engine.packet.buttons, .a, "first frame is a press")
        engine.tick(10.06)
        XCTAssertEqual(engine.packet.buttons, [])
        engine.tick(10.11)
        XCTAssertEqual(engine.packet.buttons, .a)
        engine.ended(id(a))
        XCTAssertFalse(engine.needsTicks)
        XCTAssertEqual(engine.packet.buttons, [])
    }

    func testStickOwnSizeOverridesSettings() {
        engine.leftSetup.radius = 50  // settings say 100
        _ = engine.began(id(a), at: CGPoint(x: 200, y: 300))
        _ = engine.moved(id(a), to: CGPoint(x: 225, y: 300))
        XCTAssertEqual(GamepadPacket.unit(engine.packet.lx), 0.5, accuracy: 1e-3)
    }
}
