import CryptoKit
import Foundation

public let protocolVersion: UInt8 = 2
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
        guard b.count == Self.sealedSize, b[0] == protocolVersion else { return nil }
        let body = b[0 ..< 1 + Self.size]
        let expected = Array(HMAC<SHA256>.authenticationCode(for: body, using: key)).prefix(8)
        // Constant-time compare so timing doesn't leak how many tag bytes matched.
        guard zip(expected, b[(1 + Self.size)...]).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else { return nil }
        self.init(bytes: body.dropFirst())
    }
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
