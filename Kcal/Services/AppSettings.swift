import Foundation
import Observation
import KcalCore

/// User profile and goal, persisted in UserDefaults as JSON.
@Observable
final class AppSettings {
    private static let profileKey = "energyProfile"
    private static let onboardedKey = "hasOnboarded"
    private let defaults: UserDefaults

    var profile: EnergyProfile {
        didSet { save() }
    }

    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Self.onboardedKey) }
    }

    var target: DailyTarget { EnergyMath.dailyTarget(profile) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode(EnergyProfile.self, from: data) {
            profile = saved
        } else {
            profile = EnergyProfile()
        }
        hasOnboarded = defaults.bool(forKey: Self.onboardedKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }
}
