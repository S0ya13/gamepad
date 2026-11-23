import CryptoKit
import Foundation
import Network
import SharedProtocol

/// Receives signed packets from the paired phone and drives the current backend. Main queue only.
public final class GamepadServer {
    /// Swapping it releases everything the previous backend held.
    public var backend: InputBackend {
        willSet { backend.reset() }
    }
    /// The phone's address when it starts sending, nil when it goes silent.
    public var onClient: ((String?) -> Void)?
    /// A sender without the key (not paired, or an old app version). Once per address.
    public var onRejected: ((String) -> Void)?

    public private(set) var pairing: Pairing
    private var key: SymmetricKey
    private var listener: NWListener?

    // One client at a time: a second sender is ignored until the current one goes silent,
    // otherwise two senders would flip the state (and the keys) on every packet.
    private var active: NWConnection?
    // Shared by all connections: the phone's seq follows its clock, so a replay from a new port is still old.
    private var lastSeq: UInt32?
    private var warned = Set<String>()
    private var lastPacketAt: UInt64 = 0
    private var released = true
    private let watchdog = DispatchSource.makeTimerSource(queue: .main)

    private static let silenceLimit: UInt64 = 250_000_000  // 5 missed heartbeats

    public init(pairing: Pairing, backend: InputBackend) {
        self.pairing = pairing
        key = pairing.symmetricKey
        self.backend = backend
        watchdog.schedule(deadline: .now(), repeating: .milliseconds(50))
        watchdog.setEventHandler { [weak self] in self?.checkSilence() }
        watchdog.resume()
    }

    deinit { watchdog.cancel() }

    public func start(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) throws {
        let listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: pairing.port)!)
        // Paired phones find the Mac by name, so a changed IP doesn't matter.
        listener.service = NWListener.Service(name: pairing.name, type: bonjourServiceType)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.receive(on: conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: onReady()
            case .failed(let error): onFailure("\(error)")
            default: break
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    /// Releases everything and closes the port.
    public func stop() {
        backend.reset()
        active?.cancel()
        listener?.cancel()
        listener = nil
    }

    /// After `--new-key` / "New key": phones with the old key are dropped at once.
    public func updatePairing(_ new: Pairing) {
        pairing = new
        key = new.symmetricKey
        lastSeq = nil
        active?.cancel()
        active = nil
        release()
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            guard let data, let p = GamepadPacket(sealed: data, key: self.key) else {
                if data != nil, self.warned.insert("\(conn.endpoint)").inserted { self.onRejected?("\(conn.endpoint)") }
                conn.cancel()
                return
            }
            self.handle(p, from: conn)
            if error == nil { self.receive(on: conn) }
        }
    }

    private func handle(_ p: GamepadPacket, from conn: NWConnection) {
        // Before the takeover: a replayed old packet must not even claim the slot.
        guard lastSeq.map({ GamepadPacket.isNewer(p.seq, than: $0) }) ?? true else { return }
        if conn !== active {
            guard released else { return }  // another phone is playing
            active?.cancel()
            active = conn
            onClient?("\(conn.endpoint)")
        }
        lastSeq = p.seq
        lastPacketAt = DispatchTime.now().uptimeNanoseconds
        released = false
        backend.apply(p)
    }

    private func checkSilence() {
        if !released && DispatchTime.now().uptimeNanoseconds - lastPacketAt > Self.silenceLimit { release() }
    }

    private func release() {
        guard !released else { return }
        backend.reset()
        released = true
        onClient?(nil)
    }

    // MARK: - Pairing data

    public static var serviceName: String { Host.current().localizedName ?? "Mac" }

    /// The stored pairing (or a new one), with this Mac's current name and Wi-Fi/Ethernet addresses.
    public static func loadPairing(port: UInt16, rotate: Bool) throws -> (pairing: Pairing, created: Bool) {
        let (key, created) = try PairingKeyStore.load(rotate: rotate)
        let hosts = localIPv4().filter { $0.interface.hasPrefix("en") }.map(\.ip)
        return (Pairing(key: key, name: serviceName, hosts: hosts, port: port), created)
    }

    public static func localIPv4() -> [(ip: String, interface: String)] {
        var result: [(ip: String, interface: String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }
        var cursor = head
        while let ifa = cursor?.pointee {
            defer { cursor = ifa.ifa_next }
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0, ifa.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append((String(cString: host), String(cString: ifa.ifa_name)))
            }
        }
        return result
    }
}
