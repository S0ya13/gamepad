import Foundation
import Network
import SharedProtocol

let usage = """
usage: MacServer [--debug] [--port N] [--sens PX]
  --debug     print gamepad state instead of emulating keyboard/mouse
  --port N    UDP port (default \(GamepadPacket.defaultPort))
  --sens PX   mouse pixels per tick (120 Hz) at full right-stick deflection (default 15)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n\n" + usage + "\n").utf8))
    exit(2)
}

var port = GamepadPacket.defaultPort
var debug = false
var sensitivity = 15.0
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--debug": debug = true
    case "--port":
        guard let v = args.next(), let p = UInt16(v), p > 0 else { fail("--port needs 1...65535") }
        port = p
    case "--sens":
        guard let v = args.next(), let s = Double(v), s > 0, s.isFinite else { fail("--sens needs a positive number") }
        sensitivity = s
    case "-h", "--help": print(usage); exit(0)
    default: fail("unknown argument: \(arg)")
    }
}

let backend: InputBackend = debug ? DebugBackend() : CGEventBackend(sensitivity: sensitivity)

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

// One client at a time: a second sender is ignored until the current one goes silent (watchdog),
// otherwise two senders would flip the state (and the keys) on every packet.
var active: NWConnection?

func receive(on conn: NWConnection, lastSeq: UInt32?) {
    conn.receiveMessage { data, _, _, error in
        var last = lastSeq
        if conn === active, let data, let p = GamepadPacket(bytes: data),
           last.map({ GamepadPacket.isNewer(p.seq, than: $0) }) ?? true {
            last = p.seq
            lastPacketAt = DispatchTime.now().uptimeNanoseconds
            released = false
            backend.apply(p)
        }
        if error == nil, conn === active { receive(on: conn, lastSeq: last) }
    }
}

let listener: NWListener
do {
    listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port)!)
} catch {
    fail("cannot listen on UDP \(port): \(error)")
}

listener.newConnectionHandler = { conn in
    // A restarted app gets a new source port -> new connection -> fresh sequence tracking.
    guard active == nil || released else {
        conn.cancel()
        return
    }
    active?.cancel()
    active = conn
    // Claim the slot now, before its first packet is read, so a second sender can't race in.
    released = false
    lastPacketAt = DispatchTime.now().uptimeNanoseconds
    if debug { print("\nclient: \(conn.endpoint)") }
    conn.start(queue: .main)
    receive(on: conn, lastSeq: nil)
}

listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        print("listening on UDP \(port) — enter one of these IPs on the iPhone: \(localIPv4().joined(separator: ", "))")
        print(debug ? "mode: debug" : "mode: keyboard/mouse (sens \(sensitivity))")
    case .failed(let error):
        fail("listener failed: \(error)")
    default:
        break
    }
}
listener.start(queue: .main)

func localIPv4() -> [String] {
    var result: [String] = []
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
            result.append("\(String(cString: host)) (\(String(cString: ifa.ifa_name)))")
        }
    }
    return result
}

dispatchMain()
