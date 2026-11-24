import Foundation
import GamepadServerKit
import ServiceManagement
import SharedProtocol

/// Owns the server and the settings the menu shows. Main thread only.
final class AppModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case keyboard, gamepadSDL, gamepadGC
        var id: String { rawValue }
        var title: String {
            switch self {
            case .keyboard: "Keyboard & mouse"
            case .gamepadSDL: "Gamepad: Steam / SDL games"
            case .gamepadGC: "Gamepad: Apple GameController games"
            }
        }
    }

    @Published private(set) var client: String?
    @Published private(set) var problem: String?
    @Published private(set) var pairing: Pairing?
    @Published private(set) var hasAccessibility = CGEventBackend.hasAccessibility(prompt: false)
    @Published var showPairing: Bool
    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            server?.backend = makeBackend()
        }
    }
    @Published var sensitivity: Double {
        didSet {
            UserDefaults.standard.set(sensitivity, forKey: "sensitivity")
            (server?.backend as? CGEventBackend)?.pixelsPerTick = sensitivity
        }
    }

    private var server: GamepadServer?
    // A menu bar app without windows gets App Nap, which delays its timers and network handling
    // while a fullscreen game runs; input must reach the game at once.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Relays the phone's gamepad input")

    init() {
        mode = UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? .keyboard
        sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 15
        showPairing = !UserDefaults.standard.bool(forKey: "everConnected")
        do {
            let (loaded, _) = try GamepadServer.loadPairing(port: GamepadPacket.defaultPort, rotate: false)
            pairing = loaded
            let server = GamepadServer(pairing: loaded, backend: makeBackend())
            server.onClient = { [weak self] client in
                self?.client = client
                if client != nil { UserDefaults.standard.set(true, forKey: "everConnected") }
            }
            server.onRejected = { [weak self] sender in
                self?.problem = "Ignoring \(sender): not paired with this Mac or an old app version. Scan the QR code again."
            }
            try server.start(onReady: {}, onFailure: { [weak self] error in
                self?.problem = "Can't listen on UDP \(GamepadPacket.defaultPort): \(error). Is MacServer already running in a terminal?"
            })
            self.server = server
        } catch {
            problem = "Can't start: \(error.localizedDescription)"
        }
        // The grant happens in System Settings while the menu may stay open; pick it up without a relaunch.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.refreshAccessibility()
            if self.hasAccessibility { timer.invalidate() }
        }
    }

    /// Makes a new key: every paired phone must scan the new QR code.
    func newKey() {
        guard let (fresh, _) = try? GamepadServer.loadPairing(port: GamepadPacket.defaultPort, rotate: true) else {
            problem = "Can't write a new key to \(PairingKeyStore.file.path)"
            return
        }
        pairing = fresh
        server?.updatePairing(fresh)
        showPairing = true
    }

    /// Half a second of game-style rumble, to check the phone side without a game.
    func testRumble() {
        server?.rumble(low: 200, high: 100)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.server?.rumble(low: 0, high: 0) }
    }

    func refreshAccessibility(prompt: Bool = false) {
        let granted = CGEventBackend.hasAccessibility(prompt: prompt)
        if granted != hasAccessibility { hasAccessibility = granted }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                problem = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    func quit() {
        server?.stop()  // release held keys and remove the virtual gamepad
        exit(0)
    }

    private func makeBackend() -> InputBackend {
        problem = nil
        let onFailure: (String) -> Void = { [weak self] message in self?.problem = message }
        let onRecovered: () -> Void = { [weak self] in self?.problem = nil }
        let onRumble: (UInt8, UInt8) -> Void = { [weak self] low, high in self?.server?.rumble(low: low, high: high) }
        switch mode {
        case .keyboard: return CGEventBackend(sensitivity: sensitivity)
        case .gamepadSDL:
            return OJDBackend(profile: "sdl-compatible", onFailure: onFailure, onRecovered: onRecovered, onRumble: onRumble)
        case .gamepadGC:
            return OJDBackend(profile: "game-controller-compatible", onFailure: onFailure, onRecovered: onRecovered, onRumble: onRumble)
        }
    }
}
