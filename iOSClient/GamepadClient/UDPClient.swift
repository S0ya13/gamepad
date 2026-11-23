import Foundation
import Network
import SharedProtocol

/// Sends the gamepad state on every change plus a 50 ms heartbeat. Main-thread API.
final class UDPClient {
    /// Human-readable connection status (main thread).
    var onStatus: ((String) -> Void)?

    private let queue = DispatchQueue(label: "udp", qos: .userInteractive)
    private var connection: NWConnection?
    private var host = ""
    private var state = GamepadPacket()
    private let heartbeat = DispatchSource.makeTimerSource(queue: .main)

    init() {
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(2))
        heartbeat.setEventHandler { [weak self] in self?.transmit() }
        heartbeat.resume()
    }

    func connect(host: String) {
        self.host = host
        connection?.cancel()
        let params = NWParameters.udp
        params.serviceClass = .interactiveVoice  // WMM voice queue: lowest Wi-Fi latency class
        let c = NWConnection(host: NWEndpoint.Host(host),
                             port: NWEndpoint.Port(rawValue: GamepadPacket.defaultPort)!,
                             using: params)
        c.stateUpdateHandler = { [weak self] s in
            DispatchQueue.main.async { self?.handle(s, of: c) }
        }
        connection = c
        c.start(queue: queue)
    }

    func send(_ packet: GamepadPacket) {
        state.buttons = packet.buttons
        state.lx = packet.lx
        state.ly = packet.ly
        state.rx = packet.rx
        state.ry = packet.ry
        transmit()
    }

    private func transmit() {
        guard let connection else { return }
        state.seq &+= 1  // heartbeats too, so the server doesn't drop them as duplicates
        connection.send(content: Data(state.encoded()), completion: .idempotent)
    }

    private func handle(_ s: NWConnection.State, of c: NWConnection) {
        guard c === connection else { return }
        switch s {
        case .ready:
            onStatus?("→ \(host):\(GamepadPacket.defaultPort)")
        case .waiting(let error):
            // e.g. Local Network permission denied: Settings → Privacy → Local Network.
            onStatus?("waiting: \(error.localizedDescription)")
        case .failed(let error):
            onStatus?("failed: \(error.localizedDescription), retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, c === self.connection else { return }
                self.connect(host: self.host)
            }
        default:
            break
        }
    }
}
