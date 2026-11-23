import CryptoKit
import Foundation

public let protocolVersion: UInt8 = 3
public let bonjourServiceType = "_gamepad._udp"

extension GamepadPacket {
    public static let sealedSize = 1 + size + 8

    /// Version + payload + truncated HMAC, ready to send.
    public func sealed(key: SymmetricKey) -> [UInt8] {
        let body = [protocolVersion] + encoded()
        return body + Array(HMAC<SHA256>.authenticationCode(for: body, using: key)).prefix(8)
    }

    /// Nil unless the size, version and HMAC all match (untrusted network input).
    public init?<C: Collection>(sealed bytes: C, key: SymmetricKey) where C.Element == UInt8 {
        let b = Array(bytes)
        guard b.count == Self.sealedSize, b[0] == protocolVersion,
              tagMatches(b, bodyCount: 1 + Self.size, key: key) else { return nil }
        self.init(bytes: b[1 ..< 1 + Self.size])
    }
}

/// Mac → phone acknowledgement: version, "P", the acknowledged seq (UInt32 LE), truncated HMAC.
/// The phone measures ping from it and knows the Mac actually hears it.
public enum Pong {
    public static let size = 1 + 1 + 4 + 8
    private static let kind: UInt8 = 0x50

    public static func sealed(seq: UInt32, key: SymmetricKey) -> [UInt8] {
        var body: [UInt8] = [protocolVersion, kind]
        withUnsafeBytes(of: seq.littleEndian) { body.append(contentsOf: $0) }
        return body + Array(HMAC<SHA256>.authenticationCode(for: body, using: key)).prefix(8)
    }

    /// The acknowledged seq, or nil for anything else (untrusted network input).
    public static func open<C: Collection>(_ bytes: C, key: SymmetricKey) -> UInt32? where C.Element == UInt8 {
        let b = Array(bytes)
        guard b.count == size, b[0] == protocolVersion, b[1] == kind, tagMatches(b, bodyCount: 6, key: key) else { return nil }
        return b[2 ..< 6].withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
}

/// `b` = body + first 8 bytes of HMAC-SHA256(body). Constant-time, so timing doesn't leak how many tag bytes matched.
func tagMatches(_ b: [UInt8], bodyCount: Int, key: SymmetricKey) -> Bool {
    let expected = Array(HMAC<SHA256>.authenticationCode(for: b[..<bodyCount], using: key)).prefix(8)
    return zip(expected, b[bodyCount...]).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
}

/// What the Mac's QR code carries: `gamepad-pair://pair?k=<key>&n=<name>&h=<ip,ip>&p=<port>`.
public struct Pairing: Codable, Equatable, Sendable {
    public static let urlScheme = "gamepad-pair"

    /// 32-byte shared key.
    public var key: Data
    /// Bonjour service name of the Mac.
    public var name: String
    /// Fallback IPv4 addresses for networks without Bonjour.
    public var hosts: [String]
    public var port: UInt16

    public init(key: Data, name: String, hosts: [String], port: UInt16) {
        self.key = key
        self.name = name
        self.hosts = hosts
        self.port = port
    }

    public var symmetricKey: SymmetricKey { SymmetricKey(data: key) }

    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.urlScheme
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "k", value: key.base64URLEncoded),
            URLQueryItem(name: "n", value: name),
            URLQueryItem(name: "h", value: hosts.joined(separator: ",")),
            URLQueryItem(name: "p", value: String(port)),
        ]
        return c.url!
    }

    /// Nil for anything that isn't a well-formed pairing link (it arrives from outside the app).
    public init?(url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == Self.urlScheme, c.host == "pair" else { return nil }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let key = q["k"].flatMap(Data.init(base64URLEncoded:)), key.count == 32,
              let name = q["n"], !name.isEmpty,
              let port = q["p"].flatMap(UInt16.init), port > 0 else { return nil }
        self.init(key: key, name: name, hosts: (q["h"] ?? "").split(separator: ",").map(String.init), port: port)
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        self.init(base64Encoded: b)
    }
}
