import SharedProtocol
import XCTest
@testable import GamepadServerKit

final class OJDFrameTests: XCTestCase {
    /// Switching modes releases the backend; ojd killed on purpose must not show up as an error.
    func testReleasingBackendIsNotAFailure() throws {
        try XCTSkipIf(OJDBackend.ojdPath() == nil, "ojd not installed")
        var failure: String?
        var backend: OJDBackend? = OJDBackend(profile: "generic") { failure = $0 }
        RunLoop.main.run(until: Date() + 0.3)
        XCTAssertNil(failure, "ojd didn't start")
        backend = nil
        RunLoop.main.run(until: Date() + 0.5)
        XCTAssertNil(failure)
        _ = backend
    }

    func testNeutralFrame() {
        XCTAssertEqual(OJDBackend.frame(for: GamepadPacket()),
                       #"{"buttons":[],"dpad":[],"axes":{"LeftStickX":0.0000,"LeftStickY":-0.0000,"RightStickX":0.0000,"RightStickY":-0.0000,"LeftTrigger":0.0000,"RightTrigger":0.0000}}"#)
    }

    func testButtonsDpadAndYFlip() throws {
        let p = GamepadPacket(buttons: [.a, .y, .l3, .dpadUp, .dpadLeft, .rb, .start],
                              lx: GamepadPacket.axis(-0.5), ly: GamepadPacket.axis(1), rx: GamepadPacket.axis(0.25), ry: GamepadPacket.axis(-1),
                              lt: 0, rt: 255)
        let json = try JSONSerialization.jsonObject(with: Data(OJDBackend.frame(for: p).utf8)) as! [String: Any]
        XCTAssertEqual(json["buttons"] as? [String], ["South", "North", "LeftStickClick", "RightShoulder", "Start"])
        XCTAssertEqual(json["dpad"] as? [String], ["DpadUp", "DpadLeft"])
        let axes = json["axes"] as! [String: Double]
        XCTAssertEqual(axes["LeftStickX"]!, -0.5, accuracy: 1e-3)
        XCTAssertEqual(axes["LeftStickY"]!, -1, accuracy: 1e-3)   // stick up = OJD negative Y
        XCTAssertEqual(axes["RightStickX"]!, 0.25, accuracy: 1e-3)
        XCTAssertEqual(axes["LeftTrigger"], 0)
        XCTAssertEqual(axes["RightTrigger"], 1)
        XCTAssertEqual(axes["RightStickY"]!, 1, accuracy: 1e-3)
    }
}
