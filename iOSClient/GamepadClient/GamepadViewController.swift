import UIKit

final class GamepadViewController: UIViewController, UITextFieldDelegate {
    private static let ipKey = "macIP"

    private let pad = GamepadView()
    private let ipField = UITextField()
    private let statusLabel = UILabel()
    private let udp = UDPClient()

    override func loadView() { view = pad }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark

        ipField.text = UserDefaults.standard.string(forKey: Self.ipKey)
        ipField.placeholder = "Mac IP"
        ipField.borderStyle = .roundedRect
        ipField.backgroundColor = UIColor(white: 0.12, alpha: 1)
        ipField.textAlignment = .center
        ipField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        ipField.keyboardType = .numbersAndPunctuation
        ipField.returnKeyType = .done
        ipField.autocorrectionType = .no
        ipField.autocapitalizationType = .none
        ipField.delegate = self

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = UIColor(white: 1, alpha: 0.5)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = .black  // hides the stick divider behind the text
        statusLabel.text = ipField.text?.isEmpty == false ? "connecting…" : "enter the Mac's IP"

        // Bottom center, on the border between the two floating sticks.
        let stack = UIStackView(arrangedSubviews: [statusLabel, ipField])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            ipField.widthAnchor.constraint(equalToConstant: 150),
        ])

        pad.onChange = { [udp] packet in udp.send(packet) }
        udp.onStatus = { [weak self] text in self?.statusLabel.text = text }
        if let ip = ipField.text, !ip.isEmpty { udp.connect(host: ip) }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let ip = (textField.text ?? "").trimmingCharacters(in: .whitespaces)
        textField.text = ip
        guard !ip.isEmpty else { return }
        UserDefaults.standard.set(ip, forKey: Self.ipKey)
        statusLabel.text = "connecting…"
        udp.connect(host: ip)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    // Edge swipes go to the sticks first instead of the system (home / Control Center).
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
