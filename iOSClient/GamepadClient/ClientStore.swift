import Foundation
import SharedProtocol

/// Settings, paired Macs and link state, shared by the gamepad screen and the settings screen. Main thread only.
final class ClientStore: ObservableObject {
    struct Settings: Codable, Equatable {
        var stickRadius = 70.0
        var deadZone = 0.05
        var l3Threshold = 0.88
        var haptics = true
    }

    @Published var settings: Settings {
        didSet { save(settings, as: "settings") }
    }
    // shortcut: pairing keys sit in UserDefaults (app sandbox), not the Keychain; move them if the app is ever shared.
    @Published private(set) var pairings: [Pairing] {
        didSet { save(pairings, as: "pairings") }
    }
    @Published var activeName: String? {
        didSet { UserDefaults.standard.set(activeName, forKey: "activeName") }
    }
    /// Round trip to the Mac in ms; nil while the Mac doesn't answer.
    @Published var ping: Double?
    /// Connection problem from the network layer, if any.
    @Published var problem: String?

    var active: Pairing? { pairings.first { $0.name == activeName } ?? pairings.first }

    init() {
        settings = Self.load("settings") ?? Settings()
        pairings = Self.load("pairings") ?? []
        activeName = UserDefaults.standard.string(forKey: "activeName")
    }

    /// Re-pairing the same Mac replaces its old key.
    func add(_ pairing: Pairing) {
        pairings.removeAll { $0.name == pairing.name }
        pairings.append(pairing)
        activeName = pairing.name
    }

    func remove(at offsets: IndexSet) {
        pairings.remove(atOffsets: offsets)
        if !pairings.contains(where: { $0.name == activeName }) { activeName = pairings.first?.name }
    }

    private func save<T: Encodable>(_ value: T, as key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
