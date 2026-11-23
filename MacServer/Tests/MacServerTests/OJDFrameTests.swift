import SharedProtocol
import XCTest
@testable import MacServer

final class OJDFrameTests: XCTestCase {
    func testNeutralFrame() {
        XCTAssertEqual(OJDBackend.frame(for: GamepadPacket()),
                       #"{"buttons":[],"dpad":[],"axes":{"LeftStickX":0.0000,"LeftStickY":-0.0000,"RightStickX":0.0000,"RightStickY":-0.0000}}"#)
    }

    func testButtonsDpadAndYFlip() throws {
        let p = GamepadPacket(buttons: [.a, .y, .l3, .dpadUp, .dpadLeft],
                              lx: GamepadPacket.axis(-0.5), ly: GamepadPacket.axis(1), rx: GamepadPacket.axis(0.25), ry: GamepadPacket.axis(-1))
        let json = try JSONSerialization.jsonObject(with: Data(OJDBackend.frame(for: p).utf8)) as! [String: Any]
        XCTAssertEqual(json["buttons"] as? [String], ["South", "North", "LeftStickClick"])
        XCTAssertEqual(json["dpad"] as? [String], ["DpadUp", "DpadLeft"])
        let axes = json["axes"] as! [String: Double]
        XCTAssertEqual(axes["LeftStickX"]!, -0.5, accuracy: 1e-3)
        XCTAssertEqual(axes["LeftStickY"]!, -1, accuracy: 1e-3)   // stick up = OJD negative Y
        XCTAssertEqual(axes["RightStickX"]!, 0.25, accuracy: 1e-3)
        XCTAssertEqual(axes["RightStickY"]!, 1, accuracy: 1e-3)
    }
}
