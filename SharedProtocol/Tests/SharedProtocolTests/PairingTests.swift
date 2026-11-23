import CryptoKit
import XCTest
@testable import SharedProtocol

final class PairingTests: XCTestCase {
    private let key = SymmetricKey(data: Data(repeating: 7, count: 32))
    private let packet = GamepadPacket(buttons: [.a, .l3], lx: -100, ly: 200, rx: 3, ry: -4, seq: 42)

    func testSealedRoundTrip() {
        let wire = packet.sealed(key: key)
        XCTAssertEqual(wire.count, 23)
        XCTAssertEqual(wire[0], 2)
        XCTAssertEqual(GamepadPacket(sealed: wire, key: key), packet)
    }

    func testRejectsTamperingWrongKeyAndOldFormat() {
        let wire = packet.sealed(key: key)
        for i in wire.indices {
            var bad = wire
            bad[i] ^= 0x01
            XCTAssertNil(GamepadPacket(sealed: bad, key: key), "flipped byte \(i)")
        }
        XCTAssertNil(GamepadPacket(sealed: wire, key: SymmetricKey(data: Data(repeating: 8, count: 32))))
        XCTAssertNil(GamepadPacket(sealed: packet.encoded(), key: key), "unsigned v1 packet")
        XCTAssertNil(GamepadPacket(sealed: wire.dropLast(), key: key))
    }

    func testPong() {
        let wire = Pong.sealed(seq: 0xDEADBEEF, key: key)
        XCTAssertEqual(wire.count, 14)
        XCTAssertEqual(Pong.open(wire, key: key), 0xDEADBEEF)
        for i in wire.indices {
            var bad = wire
            bad[i] ^= 0x01
            XCTAssertNil(Pong.open(bad, key: key), "flipped byte \(i)")
        }
        XCTAssertNil(Pong.open(wire, key: SymmetricKey(data: Data(repeating: 8, count: 32))))
        XCTAssertNil(Pong.open(packet.sealed(key: key), key: key), "a gamepad packet is not a pong")
    }

    func testNextSeqFollowsClockAndNeverGoesBack() {
        XCTAssertEqual(GamepadPacket.nextSeq(after: 100, nowMilliseconds: 5000), 5000)  // relaunch jumps to clock
        XCTAssertEqual(GamepadPacket.nextSeq(after: 5000, nowMilliseconds: 5000), 5001)  // burst runs ahead
        XCTAssertEqual(GamepadPacket.nextSeq(after: 5005, nowMilliseconds: 5001), 5006)  // never behind
        XCTAssertEqual(GamepadPacket.nextSeq(after: .max, nowMilliseconds: 3), 3)        // wraps
    }

    func testPairingURLRoundTrip() {
        let pairing = Pairing(key: Data((0..<32).map { UInt8($0 * 7) }), name: "Soya's MacBook Pro",
                              hosts: ["192.168.1.5", "10.0.0.2"], port: 47900)
        XCTAssertTrue(pairing.url.absoluteString.hasPrefix("gamepad-pair://pair?"))
        XCTAssertEqual(Pairing(url: pairing.url), pairing)
    }

    func testPairingRejectsBadLinks() {
        let good = Pairing(key: Data(repeating: 1, count: 32), name: "Mac", hosts: [], port: 47900).url.absoluteString
        XCTAssertNotNil(Pairing(url: URL(string: good)!))
        for bad in [
            good.replacingOccurrences(of: "gamepad-pair", with: "https"),
            good.replacingOccurrences(of: "p=47900", with: "p=0"),
            good.replacingOccurrences(of: "n=Mac", with: "n="),
            "gamepad-pair://pair?k=AAAA&n=Mac&h=&p=47900",  // short key
        ] {
            XCTAssertNil(Pairing(url: URL(string: bad)!), bad)
        }
    }
}
