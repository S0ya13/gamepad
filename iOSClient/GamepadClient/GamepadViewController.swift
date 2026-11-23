import Combine
import CoreMotion
import SharedProtocol
import SwiftUI
import UIKit

final class GamepadViewController: UIViewController {
    private let store = ClientStore()
    private let pad = GamepadView()
    private let statusLabel = UILabel()
    private let udp = UDPClient()
    private var connected: Pairing?
    private var observation: AnyCancellable?
    private let motion = CMMotionManager()
    private var tiltOn = false
    private let rumble = RumblePlayer()

    override func loadView() { view = pad }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = UIColor(white: 1, alpha: 0.5)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        let gear = UIButton(type: .system)
        gear.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        gear.tintColor = UIColor(white: 1, alpha: 0.5)
        gear.accessibilityLabel = "Settings"
        gear.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let bar = UIStackView(arrangedSubviews: [statusLabel, gear])
        bar.spacing = 4
        bar.alignment = .center
        bar.backgroundColor = .black  // hides the stick divider behind it
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        // Bottom center, on the border between the two floating sticks.
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            gear.widthAnchor.constraint(equalToConstant: 44),
            gear.heightAnchor.constraint(equalToConstant: 44),
        ])

        pad.onChange = { [udp] packet in udp.send(packet) }
        udp.onPing = { [store] in store.ping = $0 }
        udp.onProblem = { [store] in store.problem = $0 }
        udp.onRumble = { [store, rumble] low, high in
            if store.settings.haptics { rumble.play(low: low, high: high) }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [udp] _ in udp.resume() }
        // objectWillChange fires before the new value is stored, so read the store on the next turn.
        observation = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    /// A `gamepad-pair://` link from the Mac's QR code, opened with the Camera app.
    func pair(with url: URL) {
        guard let pairing = Pairing(url: url) else {
            store.problem = "not a valid pairing link"
            return
        }
        store.add(pairing)
    }

    private func refresh() {
        let s = store.settings
        if pad.engine.stickRadius != s.stickRadius {
            pad.engine.stickRadius = s.stickRadius
            pad.setNeedsDisplay()
        }
        pad.engine.deadZone = s.deadZone
        pad.engine.l3Threshold = s.l3Threshold
        pad.haptics = s.haptics

        let profile = store.profile
        if pad.engine.layout != profile.controls {
            pad.engine.layout = profile.controls
            pad.setNeedsDisplay()
        }
        udp.keyMap = profile.keys
        steer(profile.tilt)

        if store.active != connected {
            connected = store.active
            if let connected { udp.connect(connected) } else { udp.disconnect() }
        }

        guard let mac = connected else {
            statusLabel.text = "Not paired: tap ⚙ and scan the QR code\nfrom the Gamepad menu on the Mac."
            return
        }
        if let ping = store.ping {
            statusLabel.text = "● \(mac.name) · \(Int(ping.rounded())) ms"
        } else {
            statusLabel.text = "○ \(mac.name) — \(store.problem ?? "no response")"
        }
    }

    /// Racing: the phone's tilt replaces the left stick's X.
    private func steer(_ on: Bool) {
        guard on != tiltOn else { return }
        tiltOn = on
        guard on else {
            motion.stopDeviceMotionUpdates()
            pad.setTilt(nil)
            return
        }
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            // Samples already queued arrive after stop; they must not switch tilt back on.
            guard let self, self.tiltOn, let g = sample?.gravity else { return }
            let landscapeRight = self.view.window?.windowScene?.interfaceOrientation == .landscapeRight
            self.pad.setTilt(TouchEngine.steering(gravityX: g.x, gravityY: g.y, landscapeRight: landscapeRight))
        }
    }

    @objc private func openSettings() {
        let settings = UIHostingController(rootView: SettingsView(store: store) { [weak self] in
            self?.dismiss(animated: true)
        })
        settings.overrideUserInterfaceStyle = .dark
        present(settings, animated: true)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    // Edge swipes go to the sticks first instead of the system (home / Control Center).
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
