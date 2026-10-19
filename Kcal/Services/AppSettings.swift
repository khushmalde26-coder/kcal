import Foundation
import Observation
import KcalCore

/// User profile and goal, persisted in UserDefaults as JSON and mirrored to the iCloud
/// key-value store so the profile, goal and activity setting follow you between devices.
/// Without the iCloud entitlement the mirror is simply inert.
@Observable
final class AppSettings {
    private static let profileKey = "energyProfile"
    private static let onboardedKey = "hasOnboarded"
    private static let healthKey = "healthEnabled"
    private static let creditKey = "activeCredit"
    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default
    /// Keys that should be the same on every device. Health connection stays per device.
    private static let syncedKeys = [profileKey, creditKey, onboardedKey]

    var profile: EnergyProfile {
        didSet { save() }
    }

    var hasOnboarded: Bool {
        didSet { set(hasOnboarded, Self.onboardedKey) }
    }

    var healthEnabled: Bool {
        didSet { defaults.set(healthEnabled, forKey: Self.healthKey) }
    }

    /// Share of Apple Health active energy added to the budget.
    var activeCredit: Double {
        didSet { set(activeCredit, Self.creditKey) }
    }

    /// Target from the activity level, the same every day.
    var target: DailyTarget { EnergyMath.dailyTarget(profile) }

    /// The day's target plus calories earned by activity beyond the usual level.
    /// Without Health, or before active energy has loaded, nothing is earned.
    func target(activeEnergyKcal: Double?) -> DailyTarget {
        guard healthEnabled, let activeEnergyKcal else { return target }
        return EnergyMath.dailyTarget(profile, activeEnergyKcal: activeEnergyKcal, activeCredit: activeCredit)
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

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.applyCloudChanges(keys) }
        }
        cloud.synchronize()
        applyCloudChanges(Self.syncedKeys)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            set(data, Self.profileKey)
        }
    }

    private func set(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        if Self.syncedKeys.contains(key) { cloud.set(value, forKey: key) }
    }

    /// Takes values changed on another device.
    private func applyCloudChanges(_ keys: [String]) {
        for key in keys where Self.syncedKeys.contains(key) {
            guard let value = cloud.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
            switch key {
            case Self.profileKey:
                if let data = value as? Data, let saved = try? JSONDecoder().decode(EnergyProfile.self, from: data), saved != profile {
                    profile = saved
                }
            case Self.creditKey:
                if let credit = value as? Double, credit != activeCredit { activeCredit = credit }
            case Self.onboardedKey:
                // Set up on one device means set up on all.
                if (value as? Bool) == true, !hasOnboarded { hasOnboarded = true }
            default: break
            }
        }
    }
}
