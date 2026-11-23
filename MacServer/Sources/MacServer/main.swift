import CryptoKit
import Foundation
import Network
import SharedProtocol

let usage = """
usage: MacServer [--debug | --ojd sdl|gc|generic] [--port N] [--sens PX] [--pair | --new-key]
  --debug     print gamepad state instead of emulating keyboard/mouse
  --ojd KIND  analog virtual gamepad via OpenJoystickDriver ('ojd' on PATH):
              sdl = Steam/SDL games (Xbox-style), gc = Apple GameController games, generic = plain HID
  --port N    UDP port (default \(GamepadPacket.defaultPort))
  --sens PX   mouse pixels per tick (120 Hz) at full right-stick deflection (default 15)
  --pair      show the pairing QR code (also shown on first run)
  --new-key   make a new pairing key: every paired phone must scan the new QR code
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

var port = GamepadPacket.defaultPort
var debug = false
var ojdProfile: String?
var sensitivity = 15.0
var showPairing = false
var newKey = false
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--debug": debug = true
    case "--ojd":
        guard let v = args.next(), let profile = OJDBackend.profiles[v] else { fail("--ojd needs sdl, gc or generic") }
        ojdProfile = profile
    case "--port":
        guard let v = args.next(), let p = UInt16(v), p > 0 else { fail("--port needs 1...65535") }
        port = p
    case "--sens":
        guard let v = args.next(), let s = Double(v), s > 0, s.isFinite else { fail("--sens needs a positive number") }
        sensitivity = s
    case "--pair": showPairing = true
    case "--new-key": newKey = true
    case "-h", "--help": print(usage); exit(0)
    default: fail("unknown argument: \(arg)")
    }
}

if debug && ojdProfile != nil { fail("--debug and --ojd are exclusive") }
let backend: InputBackend = debug ? DebugBackend()
    : ojdProfile.map { OJDBackend(profile: $0) } ?? CGEventBackend(sensitivity: sensitivity)

// MARK: - Watchdog: release everything if the client goes silent (heartbeat is 50 ms).

let silenceLimit: UInt64 = 250_000_000
var lastPacketAt: UInt64 = 0
var released = true

let watchdog = DispatchSource.makeTimerSource(queue: .main)
watchdog.schedule(deadline: .now(), repeating: .milliseconds(50))
watchdog.setEventHandler {
    if !released && DispatchTime.now().uptimeNanoseconds - lastPacketAt > silenceLimit {
        backend.reset()
        released = true
    }
}
watchdog.resume()

// MARK: - Ctrl+C must not leave keys stuck.

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    backend.reset()
    print("\nbye")
    exit(0)
}
sigint.resume()

// MARK: - UDP listener

// MARK: - Pairing

let serviceName = Host.current().localizedName ?? "Mac"
let pairing: Pairing
do {
    let (keyData, created) = try PairingKeyStore.load(rotate: newKey)
    pairing = Pairing(key: keyData, name: serviceName,
                      hosts: localIPv4().filter { $0.interface.hasPrefix("en") }.map(\.ip), port: port)
    if created || showPairing {
        print(QRCode.terminalString(QRCode.modules(for: pairing.url.absoluteString)))
        print("Scan with the iPhone Camera and open the link in Gamepad.\(newKey ? " Phones paired before must scan again." : "")\n")
    }
} catch {
    fail("cannot read or create the pairing key at \(PairingKeyStore.file.path): \(error)")
}
let key = pairing.symmetricKey

// MARK: - UDP listener

// One client at a time: a second sender is ignored until the current one goes silent (watchdog),
// otherwise two senders would flip the state (and the keys) on every packet.
var active: NWConnection?
// Shared by all connections: the phone's seq follows its clock, so a replay from a new port is still old.
var lastSeq: UInt32?
var warned = Set<String>()

func receive(on conn: NWConnection) {
    conn.receiveMessage { data, _, _, error in
        guard let data, let p = GamepadPacket(sealed: data, key: key) else {
            if data != nil, warned.insert("\(conn.endpoint)").inserted {
                print("\nignoring \(conn.endpoint): not paired with this Mac or an old app version (run with --pair)")
            }
            conn.cancel()
            return
        }
        handle(p, from: conn)
        if error == nil { receive(on: conn) }
    }
}

func handle(_ p: GamepadPacket, from conn: NWConnection) {
    // Before the takeover: a replayed old packet must not even claim the slot.
    guard lastSeq.map({ GamepadPacket.isNewer(p.seq, than: $0) }) ?? true else { return }
    if conn !== active {
        guard released else { return }  // another phone is playing
        active?.cancel()
        active = conn
        print("\nclient: \(conn.endpoint)")
    }
    lastSeq = p.seq
    lastPacketAt = DispatchTime.now().uptimeNanoseconds
    released = false
    backend.apply(p)
}

let listener: NWListener
do {
    listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port)!)
} catch {
    fail("cannot listen on UDP \(port): \(error)")
}
// Paired phones find the Mac by name, so a changed IP doesn't matter.
listener.service = NWListener.Service(name: serviceName, type: bonjourServiceType)

listener.newConnectionHandler = { conn in
    conn.start(queue: .main)
    receive(on: conn)
}

listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        print("listening on UDP \(port) as \"\(serviceName)\" — paired phones connect automatically (--pair shows the QR code)")
        print(debug ? "mode: debug" : ojdProfile.map { "mode: virtual gamepad via OpenJoystickDriver (\($0))" }
            ?? "mode: keyboard/mouse (sens \(sensitivity))")
    case .failed(let error):
        fail("listener failed: \(error)")
    default:
        break
    }
}
listener.start(queue: .main)

func localIPv4() -> [(ip: String, interface: String)] {
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

dispatchMain()
