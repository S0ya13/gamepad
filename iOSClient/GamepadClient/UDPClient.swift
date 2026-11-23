import CryptoKit
import Foundation
import Network
import SharedProtocol

/// Sends the signed gamepad state on every change plus a 50 ms heartbeat. Main-thread API.
final class UDPClient {
    /// Connection problem, or nil when the socket is up (main thread).
    var onProblem: ((String?) -> Void)?
    /// Round trip in ms from the Mac's acknowledgements; nil when it stops answering (main thread).
    var onPing: ((Double?) -> Void)?
    /// A game's vibration: heavy and light motor levels (main thread).
    var onRumble: ((UInt8, UInt8) -> Void)?
    /// The game profile's keyboard keys; resent every second so a restarted Mac app gets them too.
    var keyMap: KeyMap? {
        didSet { if keyMap != oldValue { sendKeyMap() } }
    }

    private let queue = DispatchQueue(label: "udp", qos: .userInteractive)
    private var connection: NWConnection?
    private var pairing: Pairing?
    private var key: SymmetricKey?
    private var state = GamepadPacket(seq: GamepadPacket.nowMilliseconds())
    private let heartbeat = DispatchSource.makeTimerSource(queue: .main)
    // Recent (seq, send time) pairs, to turn an acknowledged seq into a round trip.
    private var sent = [(seq: UInt32, at: UInt64)](repeating: (0, 0), count: 256)
    private var sentIndex = 0
    private var lastPongAt: UInt64 = 0
    private var linked = false
    private var ticks = 0

    init() {
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(2))
        heartbeat.setEventHandler { [weak self] in
            guard let self else { return }
            self.transmit()
            self.checkLink()
            self.ticks += 1
            if self.ticks % 20 == 0 { self.sendKeyMap() }
        }
        heartbeat.resume()
    }

    /// Finds the Mac by its Bonjour name; falls back to the IP from the QR code when Bonjour is blocked.
    func connect(_ pairing: Pairing) {
        if self.pairing != pairing { unlink() }
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

    /// The last paired Mac was removed.
    func disconnect() {
        connection?.cancel()
        connection = nil
        pairing = nil
        key = nil
        unlink()
    }

    func send(_ packet: GamepadPacket) {
        let seq = state.seq  // the sender owns seq; everything else comes from the touch engine
        state = packet
        state.seq = seq
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
        receivePongs(on: c)
    }

    private func receivePongs(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            DispatchQueue.main.async {
                guard let self, c === self.connection else { return }
                if let data, let key = self.key {
                    if let seq = Pong.open(data, key: key) {
                        self.pong(seq)
                    } else if let motors = Rumble.open(data, key: key) {
                        self.onRumble?(motors.low, motors.high)
                    }
                }
                if error == nil { self.receivePongs(on: c) }
            }
        }
    }

    private func pong(_ seq: UInt32) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let sentAt = sent.first(where: { $0.seq == seq && $0.at > 0 })?.at else { return }
        lastPongAt = now
        linked = true
        onPing?(Double(now - sentAt) / 1e6)
    }

    /// The Mac answers 5 times a second; a second of silence means it no longer hears us.
    private func checkLink() {
        guard DispatchTime.now().uptimeNanoseconds - lastPongAt > 1_000_000_000 else { return }
        unlink()
    }

    private func unlink() {
        guard linked else { return }
        linked = false
        onPing?(nil)
    }

    private func sendKeyMap() {
        guard let connection, let key, let keyMap else { return }
        connection.send(content: Data(keyMap.sealed(key: key)), completion: .idempotent)
    }

    private func transmit() {
        guard let connection, let key else { return }
        // Clock-based seq (heartbeats too): the Mac drops replays and duplicates, even across app relaunches.
        state.seq = GamepadPacket.nextSeq(after: state.seq, nowMilliseconds: GamepadPacket.nowMilliseconds())
        sent[sentIndex] = (state.seq, DispatchTime.now().uptimeNanoseconds)
        sentIndex = (sentIndex + 1) % sent.count
        connection.send(content: Data(state.sealed(key: key)), completion: .idempotent)
    }

    private func handle(_ s: NWConnection.State, of c: NWConnection, label: String) {
        guard c === connection else { return }
        switch s {
        case .ready:
            onProblem?(nil)
        case .waiting(let error):
            // e.g. Local Network permission denied: Settings → Privacy → Local Network.
            onProblem?("waiting: \(error.localizedDescription)")
        case .failed(let error):
            onProblem?("failed: \(error.localizedDescription), retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, c === self.connection, let pairing = self.pairing else { return }
                self.connect(pairing)
            }
        default:
            break
        }
    }
}
