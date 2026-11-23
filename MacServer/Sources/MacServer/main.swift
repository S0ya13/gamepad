import Foundation
import GamepadServerKit
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

let pairing: Pairing
do {
    let (loaded, created) = try GamepadServer.loadPairing(port: port, rotate: newKey)
    pairing = loaded
    if created || showPairing {
        print(QRCode.terminalString(QRCode.modules(for: pairing.url.absoluteString)))
        print("Scan with the iPhone Camera and open the link in Gamepad.\(newKey ? " Phones paired before must scan again." : "")\n")
    }
} catch {
    fail("cannot read or create the pairing key at \(PairingKeyStore.file.path): \(error)")
}

if !debug && ojdProfile == nil && !CGEventBackend.hasAccessibility(prompt: true) {
    print("""
    No Accessibility permission.
    System Settings → Privacy & Security → Accessibility → enable the app you run this from
    (Terminal / iTerm / your IDE), then restart it. Use --debug or --ojd to run without it.
    """)
    exit(1)
}

let backend: InputBackend = debug ? DebugBackend()
    : ojdProfile.map { OJDBackend(profile: $0) { message in print("\n" + message); exit(1) } }
    ?? CGEventBackend(sensitivity: sensitivity)
let server = GamepadServer(pairing: pairing, backend: backend)
server.onClient = { client in if let client { print("\nclient: \(client)") } }
server.onRejected = { print("\nignoring \($0): not paired with this Mac or an old app version (run with --pair)") }

do {
    try server.start(onReady: {
        print("listening on UDP \(port) as \"\(pairing.name)\" — paired phones connect automatically (--pair shows the QR code)")
        print(debug ? "mode: debug" : ojdProfile.map { "mode: virtual gamepad via OpenJoystickDriver (\($0))" }
            ?? "mode: keyboard/mouse (sens \(sensitivity))")
    }, onFailure: { fail("listener failed: \($0)") })
} catch {
    fail("cannot listen on UDP \(port): \(error)")
}

// Ctrl+C must not leave keys stuck.
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    server.stop()
    print("\nbye")
    exit(0)
}
sigint.resume()

dispatchMain()
