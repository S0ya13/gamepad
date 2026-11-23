import CryptoKit
import Foundation
import Network
import SharedProtocol

/// Sends the signed gamepad state on every change plus a 50 ms heartbeat. Main-thread API.
final class UDPClient {
    /// Human-readable connection status (main thread).
    var onStatus: ((String) -> Void)?

    private let queue = DispatchQueue(label: "udp", qos: .userInteractive)
    private var connection: NWConnection?
    private var pairing: Pairing?
    private var key: SymmetricKey?
    private var state = GamepadPacket(seq: GamepadPacket.nowMilliseconds())
    private let heartbeat = DispatchSource.makeTimerSource(queue: .main)

    init() {
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(2))
        heartbeat.setEventHandler { [weak self] in self?.transmit() }
        heartbeat.resume()
    }

    /// Finds the Mac by its Bonjour name; falls back to the IP from the QR code when Bonjour is blocked.
    func connect(_ pairing: Pairing) {
        self.pairing = pairing
        key = pairing.symmetricKey
        open(.service(name: pairing.name, type: bonjourServiceType, domain: "local.", interface: nil), label: pairing.name)
        let attempt = connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let attempt, attempt === self.connection, attempt.state != .ready,
                  let host = pairing.hosts.first, let port = NWEndpoint.Port(rawValue: pairing.port) else { return }
            self.open(.hostPort(host: NWEndpoint.Host(host), port: port), label: host)
        }
    }

    /// Back from another app: iOS may have torn the socket down while we were suspended.
    func resume() {
        guard let pairing, connection?.state != .ready else { return }
        connect(pairing)
    }

    func send(_ packet: GamepadPacket) {
        state.buttons = packet.buttons
        state.lx = packet.lx
        state.ly = packet.ly
        state.rx = packet.rx
        state.ry = packet.ry
        transmit()
    }

    private func open(_ endpoint: NWEndpoint, label: String) {
        connection?.cancel()
        let params = NWParameters.udp
        params.serviceClass = .interactiveVoice  // WMM voice queue: lowest Wi-Fi latency class
        let c = NWConnection(to: endpoint, using: params)
        c.stateUpdateHandler = { [weak self] s in
            DispatchQueue.main.async { self?.handle(s, of: c, label: label) }
        }
        connection = c
        c.start(queue: queue)
    }

    private func transmit() {
        guard let connection, let key else { return }
        // Clock-based seq (heartbeats too): the Mac drops replays and duplicates, even across app relaunches.
        state.seq = GamepadPacket.nextSeq(after: state.seq, nowMilliseconds: GamepadPacket.nowMilliseconds())
        connection.send(content: Data(state.sealed(key: key)), completion: .idempotent)
    }

    private func handle(_ s: NWConnection.State, of c: NWConnection, label: String) {
        guard c === connection else { return }
        switch s {
        case .ready:
            onStatus?("→ \(label)")
        case .waiting(let error):
            // e.g. Local Network permission denied: Settings → Privacy → Local Network.
            onStatus?("waiting: \(error.localizedDescription)")
        case .failed(let error):
            onStatus?("failed: \(error.localizedDescription), retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, c === self.connection, let pairing = self.pairing else { return }
                self.connect(pairing)
            }
        default:
            break
        }
    }
}
