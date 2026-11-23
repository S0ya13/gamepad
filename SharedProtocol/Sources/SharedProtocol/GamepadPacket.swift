/// Wire format (14 bytes, little-endian, no padding):
/// offset 0  UInt16 buttons
/// offset 2  Int16  lx   (right +)
/// offset 4  Int16  ly   (up +)
/// offset 6  Int16  rx   (right +)
/// offset 8  Int16  ry   (up +)
/// offset 10 UInt32 seq  (wraps around)
public struct GamepadPacket: Equatable, Sendable {
    public struct Buttons: OptionSet, Hashable, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }

        public static let dpadUp    = Buttons(rawValue: 1 << 0)
        public static let dpadDown  = Buttons(rawValue: 1 << 1)
        public static let dpadLeft  = Buttons(rawValue: 1 << 2)
        public static let dpadRight = Buttons(rawValue: 1 << 3)
        public static let a         = Buttons(rawValue: 1 << 4)
        public static let b         = Buttons(rawValue: 1 << 5)
        public static let x         = Buttons(rawValue: 1 << 6)
        public static let y         = Buttons(rawValue: 1 << 7)
        public static let l3        = Buttons(rawValue: 1 << 8)
        public static let r3        = Buttons(rawValue: 1 << 9)
    }

    public static let size = 14
    public static let defaultPort: UInt16 = 47900

    public var buttons: Buttons
    public var lx: Int16
    public var ly: Int16
    public var rx: Int16
    public var ry: Int16
    public var seq: UInt32

    public init(buttons: Buttons = [], lx: Int16 = 0, ly: Int16 = 0, rx: Int16 = 0, ry: Int16 = 0, seq: UInt32 = 0) {
        self.buttons = buttons
        self.lx = lx
        self.ly = ly
        self.rx = rx
        self.ry = ry
        self.seq = seq
    }

    public func encoded() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(Self.size)
        func put<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
        }
        put(buttons.rawValue); put(lx); put(ly); put(rx); put(ry); put(seq)
        return out
    }

    /// Returns nil for anything that is not exactly `size` bytes (untrusted network input).
    public init?<C: Collection>(bytes: C) where C.Element == UInt8 {
        let b = Array(bytes)
        guard b.count == Self.size else { return nil }
        func get<T: FixedWidthInteger>(_ offset: Int) -> T {
            b.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
        }
        self.init(buttons: Buttons(rawValue: get(0)), lx: get(2), ly: get(4), rx: get(6), ry: get(8), seq: get(10))
    }

    /// -1...1 -> -32767...32767 (symmetric; -32768 is never produced).
    public static func axis(_ v: Double) -> Int16 {
        guard v.isFinite else { return 0 }
        return Int16((min(max(v, -1), 1) * 32767).rounded())
    }

    /// Raw axis -> -1...1.
    public static func unit(_ raw: Int16) -> Double {
        max(-1, Double(raw) / 32767)
    }

    /// Wrap-around-safe "seq came after last" (RFC 1982 style).
    public static func isNewer(_ seq: UInt32, than last: UInt32) -> Bool {
        Int32(bitPattern: seq &- last) > 0
    }
}
