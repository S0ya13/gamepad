import SharedProtocol
import UIKit

final class GamepadViewController: UIViewController {
    private static let pairingKey = "pairing"

    private let pad = GamepadView()
    private let statusLabel = UILabel()
    private let udp = UDPClient()

    override func loadView() { view = pad }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = UIColor(white: 1, alpha: 0.5)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.backgroundColor = .black  // hides the stick divider behind the text
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        // Bottom center, on the border between the two floating sticks.
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])

        pad.onChange = { [udp] packet in udp.send(packet) }
        udp.onStatus = { [weak self] text in self?.statusLabel.text = text }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [udp] _ in udp.resume() }

        // shortcut: the key sits in UserDefaults (app sandbox), not the Keychain; move it if the app is ever shared.
        if let data = UserDefaults.standard.data(forKey: Self.pairingKey),
           let pairing = try? JSONDecoder().decode(Pairing.self, from: data) {
            statusLabel.text = "connecting to \(pairing.name)…"
            udp.connect(pairing)
        } else {
            statusLabel.text = "Not paired. Run MacServer --pair on the Mac\nand scan the QR code with the Camera."
        }
    }

    /// A `gamepad-pair://` link from the Mac's QR code.
    func pair(with url: URL) {
        guard let pairing = Pairing(url: url) else {
            statusLabel.text = "This is not a valid pairing link."
            return
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(pairing), forKey: Self.pairingKey)
        statusLabel.text = "paired with \(pairing.name), connecting…"
        udp.connect(pairing)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    // Edge swipes go to the sticks first instead of the system (home / Control Center).
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
