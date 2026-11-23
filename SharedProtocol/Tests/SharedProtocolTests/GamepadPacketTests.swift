import XCTest
@testable import SharedProtocol

final class GamepadPacketTests: XCTestCase {
    func testExactLittleEndianLayout() {
        let p = GamepadPacket(buttons: [.dpadUp, .l3, .back], lx: 1, ly: -1, rx: 0x1234, ry: -32768,
                              lt: 0x7F, rt: 0xFF, seq: 0xA1B2C3D4)
        XCTAssertEqual(p.encoded(), [
            0x01, 0x21,             // buttons = 0x2101
            0x01, 0x00,             // lx = 1
            0xFF, 0xFF,             // ly = -1
            0x34, 0x12,             // rx = 0x1234
            0x00, 0x80,             // ry = -32768
            0x7F, 0xFF,             // lt, rt
            0xD4, 0xC3, 0xB2, 0xA1, // seq
        ])
    }

    func testRoundTrip() {
        let p = GamepadPacket(buttons: [.a, .y, .r3, .lb, .rb, .start], lx: 32767, ly: -32767, rx: -5, ry: 100, lt: 1, rt: 200, seq: .max)
        XCTAssertEqual(GamepadPacket(bytes: p.encoded()), p)
    }

    func testRejectsWrongSize() {
        XCTAssertNil(GamepadPacket(bytes: [UInt8](repeating: 0, count: 15)))
        XCTAssertNil(GamepadPacket(bytes: [UInt8](repeating: 0, count: 17)))
        XCTAssertNil(GamepadPacket(bytes: [UInt8]()))
    }

    func testDecodesFromSliceWithNonZeroStartIndex() {
        let bytes = [0xEE] + GamepadPacket(seq: 7).encoded()
        XCTAssertEqual(GamepadPacket(bytes: bytes.dropFirst())?.seq, 7)
    }

    func testAxisConversion() {
        XCTAssertEqual(GamepadPacket.axis(1), 32767)
        XCTAssertEqual(GamepadPacket.axis(-1), -32767)
        XCTAssertEqual(GamepadPacket.axis(5), 32767)
        XCTAssertEqual(GamepadPacket.axis(-5), -32767)
        XCTAssertEqual(GamepadPacket.axis(0), 0)
        XCTAssertEqual(GamepadPacket.axis(.nan), 0)
        XCTAssertEqual(GamepadPacket.unit(-32768), -1)
        XCTAssertEqual(GamepadPacket.unit(32767), 1)
        XCTAssertEqual(GamepadPacket.unit(GamepadPacket.axis(0.5)), 0.5, accuracy: 1e-4)
        XCTAssertEqual(GamepadPacket.trigger(1), 255)
        XCTAssertEqual(GamepadPacket.trigger(-1), 0)
        XCTAssertEqual(GamepadPacket.trigger(.nan), 0)
        XCTAssertEqual(GamepadPacket.trigger(0.5), 128)
    }

    func testSequenceWrapAround() {
        XCTAssertTrue(GamepadPacket.isNewer(2, than: 1))
        XCTAssertFalse(GamepadPacket.isNewer(1, than: 2))
        XCTAssertFalse(GamepadPacket.isNewer(5, than: 5))
        XCTAssertTrue(GamepadPacket.isNewer(0, than: .max))
        XCTAssertTrue(GamepadPacket.isNewer(3, than: .max - 3))
        XCTAssertFalse(GamepadPacket.isNewer(.max, than: 0))
    }
}
