import Foundation
import SharedProtocol

/// Settings, paired Macs and link state, shared by the gamepad screen and the settings screen. Main thread only.
final class ClientStore: ObservableObject {
    struct Settings: Codable, Equatable {
        var stickRadius = 55.0
        var deadZone = 0.05
        var l3Threshold = 0.88
        /// Off by default: a stick that follows the finger sits at its edge, so L3 would hold almost always.
        var l3Push = false
        var haptics = true
        /// Camera swipe speed multiplier.
        var swipeSpeed = 1.0
    }

    @Published var settings: Settings {
        didSet { save(settings, as: "settings") }
    }
    // shortcut: pairing keys sit in UserDefaults (app sandbox), not the Keychain; move them if the app is ever shared.
    @Published private(set) var pairings: [Pairing] {
        didSet { save(pairings, as: "pairings") }
    }
    /// Game profiles: layout, tilt and keyboard keys each.
    @Published var profiles: [Profile] {
        didSet { save(profiles, as: "profiles") }
    }
    @Published var activeProfileID: UUID {
        didSet { UserDefaults.standard.set(activeProfileID.uuidString, forKey: "activeProfile") }
    }
    @Published var activeName: String? {
        didSet { UserDefaults.standard.set(activeName, forKey: "activeName") }
    }
    /// Round trip to the Mac in ms; nil while the Mac doesn't answer.
    @Published var ping: Double?
    /// Connection problem from the network layer, if any.
    @Published var problem: String?

    var active: Pairing? { pairings.first { $0.name == activeName } ?? pairings.first }

    /// The selected game profile; editing it saves it.
    var profile: Profile {
        get { profiles.first { $0.id == activeProfileID } ?? profiles[0] }
        set {
            guard let i = profiles.firstIndex(where: { $0.id == newValue.id }) else { return }
            profiles[i] = newValue
        }
    }

    init() {
        settings = Self.load("settings") ?? Settings()
        pairings = Self.load("pairings") ?? []
        activeName = UserDefaults.standard.string(forKey: "activeName")
        let saved: [Profile] = Self.load("profiles") ?? []
        var profiles = saved.isEmpty ? [.controller, .standard, .racing] : saved
        // Installs from before the Controller preset get it once; deleting it later sticks.
        if !UserDefaults.standard.bool(forKey: "hasControllerPreset") {
            if !profiles.contains(where: { $0.name == Profile.controller.name }) { profiles.insert(.controller, at: 0) }
            UserDefaults.standard.set(true, forKey: "hasControllerPreset")
        }
        self.profiles = profiles
        let savedID = UserDefaults.standard.string(forKey: "activeProfile").flatMap(UUID.init)
        activeProfileID = profiles.contains { $0.id == savedID } ? savedID! : profiles[0].id
        // didSet doesn't run in init: store built-in and migrated profiles now, or their ids change next launch.
        // Never over data that failed to decode: that would wipe the user's layouts.
        let unreadable = saved.isEmpty && UserDefaults.standard.data(forKey: "profiles") != nil
        if !unreadable { save(profiles, as: "profiles") }
    }

    /// A copy of the current profile becomes the current one, so a new game starts from a working layout.
    func duplicateProfile() {
        var copy = profile
        copy.id = UUID()
        copy.name += " copy"
        profiles.append(copy)
        activeProfileID = copy.id
    }

    func deleteProfile() {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        activeProfileID = profiles[0].id
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

// Settings saved by older builds lack newer fields; they keep their values instead of resetting.
extension ClientStore.Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        stickRadius = try c.decodeIfPresent(Double.self, forKey: .stickRadius) ?? d.stickRadius
        deadZone = try c.decodeIfPresent(Double.self, forKey: .deadZone) ?? d.deadZone
        l3Threshold = try c.decodeIfPresent(Double.self, forKey: .l3Threshold) ?? d.l3Threshold
        l3Push = try c.decodeIfPresent(Bool.self, forKey: .l3Push) ?? d.l3Push
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        swipeSpeed = try c.decodeIfPresent(Double.self, forKey: .swipeSpeed) ?? d.swipeSpeed
    }
}
