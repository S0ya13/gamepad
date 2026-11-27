import SharedProtocol
import XCTest
@testable import GamepadServerKit

final class OJDFrameTests: XCTestCase {
    /// E2004: ojd is installed but its service isn't running, so there is nothing to test against.
    private func skipIfServiceStopped(_ failure: String?) throws {
        try XCTSkipIf(failure?.contains("E2004") == true, "OJD service not running ('ojd service start')")
    }

    /// Switching modes releases the backend; ojd killed on purpose must not show up as an error.
    func testReleasingBackendIsNotAFailure() throws {
        try XCTSkipIf(OJDBackend.ojdPath() == nil, "ojd not installed")
        var failure: String?
        var backend: OJDBackend? = OJDBackend(profile: "generic") { failure = $0 }
        RunLoop.main.run(until: Date() + 0.3)
        try skipIfServiceStopped(failure)
        XCTAssertNil(failure, "ojd didn't start")
        backend = nil
        RunLoop.main.run(until: Date() + 0.5)
        XCTAssertNil(failure)
        _ = backend
    }

    /// OJD closes a feed when it can't deliver a frame (a GeForce NOW game starting); the pad must come back by itself.
    func testExitedFeedRestarts() throws {
        try XCTSkipIf(OJDBackend.ojdPath() == nil, "ojd not installed")
        OJDBackend.restartDelay = 0.2
        defer { OJDBackend.restartDelay = 1 }
        var failure: String?
        var recovered = false
        let backend = OJDBackend(profile: "generic", onFailure: { failure = $0 }, onRecovered: { recovered = true })
        RunLoop.main.run(until: Date() + 0.5)
        try skipIfServiceStopped(failure)
        let first = try XCTUnwrap(backend.runningPID, "ojd didn't start")
        kill(first, SIGKILL)
        RunLoop.main.run(until: Date() + 1.5)
        XCTAssertNotNil(failure)
        XCTAssertTrue(recovered)
        XCTAssertNotNil(backend.runningPID)
        XCTAssertNotEqual(backend.runningPID, first)
    }

    /// The pipe is non-blocking; only a write under PIPE_BUF is all-or-nothing, so a frame never arrives cut in half.
    func testLongestFrameFitsOneAtomicWrite() {
        let all = GamepadPacket(buttons: GamepadPacket.Buttons(rawValue: .max),
                                lx: .min, ly: .min, rx: .min, ry: .min, lt: 255, rt: 255)
        XCTAssertLessThan(OJDBackend.frame(for: all).utf8.count + 1, Int(PIPE_BUF))
    }

    func testRumbleLines() {
        func parse(_ s: String) -> (low: UInt8, high: UInt8, milliseconds: Int?)? { OJDBackend.rumble(fromLine: Data(s.utf8)) }
        let set = parse(#"{"apiVersion":"openjoystickdriver/v1alpha3","kind":"RumbleCommand","type":"SetRumble","intensities":{"lowFrequency":65535,"highFrequency":257},"durationMilliseconds":120}"#)
        XCTAssertEqual(set?.low, 255)
        XCTAssertEqual(set?.high, 1)
        XCTAssertEqual(set?.milliseconds, 120)
        let stop = parse(#"{"apiVersion":"openjoystickdriver/v1alpha3","kind":"RumbleCommand","type":"StopRumble"}"#)
        XCTAssertEqual(stop?.low, 0)
        XCTAssertNil(stop?.milliseconds)
        XCTAssertEqual(parse(#"{"type":"SetRumble","intensities":{"lowFrequency":99999999}}"#)?.low, 255, "clamped")
        XCTAssertNil(parse(#"{"type":"SetPlayerIndex"}"#))
        XCTAssertNil(parse("not json"))
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
