import Foundation
import Observation
import KcalCore

/// User profile and goal, persisted in UserDefaults as JSON.
@Observable
final class AppSettings {
    private static let profileKey = "energyProfile"
    private static let onboardedKey = "hasOnboarded"
    private static let healthKey = "healthEnabled"
    private static let creditKey = "activeCredit"
    private let defaults: UserDefaults

    var profile: EnergyProfile {
        didSet { save() }
    }

    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Self.onboardedKey) }
    }

    var healthEnabled: Bool {
        didSet { defaults.set(healthEnabled, forKey: Self.healthKey) }
    }

    /// Share of Apple Health active energy added to the budget.
    var activeCredit: Double {
        didSet { defaults.set(activeCredit, forKey: Self.creditKey) }
    }

    /// Target from the activity level. With Health on, use `target(activeEnergyKcal:)`.
    var target: DailyTarget { EnergyMath.dailyTarget(profile) }

    /// Today's budget: with Health on, resting plus food plus credited activity.
    /// Nil active energy (not loaded yet) counts as none.
    func target(activeEnergyKcal: Double?) -> DailyTarget {
        guard healthEnabled else { return target }
        return EnergyMath.dailyTarget(profile, activeEnergyKcal: activeEnergyKcal ?? 0, activeCredit: activeCredit)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode(EnergyProfile.self, from: data) {
            profile = saved
        } else {
            profile = EnergyProfile()
        }
        hasOnboarded = defaults.bool(forKey: Self.onboardedKey)
        healthEnabled = defaults.bool(forKey: Self.healthKey)
        activeCredit = defaults.object(forKey: Self.creditKey) as? Double ?? 0.75
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }
}
