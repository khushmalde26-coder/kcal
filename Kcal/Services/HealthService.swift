import Foundation
import HealthKit
import Observation
import SwiftData

/// Apple Health: reads active energy and weight, writes logged food and weigh-ins.
/// Every call is a no-op when Health is unavailable or switched off in Settings,
/// and failures (including denied permissions) are swallowed so logging never blocks.
@Observable
final class HealthService {
    static let isAvailable = HKHealthStore.isHealthDataAvailable()

    private let settings: AppSettings
    private let store = HKHealthStore()
    /// Active energy keyed by start of day.
    private var activeEnergyByDay: [Date: Double] = [:]

    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let dietary: [(type: HKQuantityType, unit: HKUnit, suffix: String, value: (LogEntry) -> Double)] = [
        (HKQuantityType(.dietaryEnergyConsumed), .kilocalorie(), "energy", \.kcal),
        (HKQuantityType(.dietaryProtein), .gram(), "protein", \.protein),
        (HKQuantityType(.dietaryCarbohydrates), .gram(), "carbs", \.carbs),
        (HKQuantityType(.dietaryFatTotal), .gram(), "fat", \.fat),
    ]

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var isOn: Bool { Self.isAvailable && settings.healthEnabled }

    // MARK: Permission

    /// Shows the Health permission sheet. Returns false only if Health is unavailable
    /// or the request itself failed; iOS never reveals whether reading was allowed.
    func connect() async -> Bool {
        guard Self.isAvailable else { return false }
        let share: Set<HKSampleType> = Set(Self.dietary.map(\.type)).union([Self.bodyMass])
        let read: Set<HKObjectType> = [Self.activeEnergy, Self.bodyMass]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    // MARK: Active energy

    /// Cached active energy for the day, or nil if Health is off or it hasn't loaded yet.
    func activeEnergy(on day: Date) -> Double? {
        guard isOn else { return nil }
        return activeEnergyByDay[Calendar.current.startOfDay(for: day)]
    }

    func refreshActiveEnergy(on day: Date) async {
        guard isOn else { return }
        let start = Calendar.current.startOfDay(for: day)
        #if DEBUG
        // For simulator screenshots: KCAL_MOCK_ACTIVE_KCAL=1000 in the launch environment.
        if let mock = ProcessInfo.processInfo.environment["KCAL_MOCK_ACTIVE_KCAL"].flatMap(Double.init) {
            activeEnergyByDay[start] = mock
            return
        }
        #endif
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: Self.activeEnergy, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum
        )
        // No samples (or no read permission) comes back as nil or an error: both mean nothing burned yet.
        let kcal = (try? await descriptor.result(for: store))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        activeEnergyByDay[start] = kcal ?? 0
    }

    /// Yields whenever new active energy reaches Health, until the calling task is cancelled.
    func activeEnergyChanges() -> AsyncStream<Void> {
        guard isOn else { return AsyncStream { $0.finish() } }
        return Self.observe(Self.activeEnergy, in: store)
    }

    /// Built outside the main actor because HealthKit calls the handler on its own queue.
    nonisolated private static func observe(_ type: HKSampleType, in store: HKHealthStore) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { continuation.yield() }
                completion()
            }
            store.execute(query)
            continuation.onTermination = { _ in store.stop(query) }
        }
    }

    // MARK: Food

    func save(_ entries: [LogEntry]) async {
        guard isOn else { return }
        var samples: [HKQuantitySample] = []
        for entry in entries {
            let id = entry.healthSyncID ?? UUID().uuidString
            for field in Self.dietary where canWrite(field.type) {
                samples.append(HKQuantitySample(
                    type: field.type,
                    quantity: HKQuantity(unit: field.unit, doubleValue: field.value(entry)),
                    start: entry.timestamp,
                    end: entry.timestamp,
                    metadata: [
                        // One identifier per nutrient: samples sharing an identifier replace each other.
                        HKMetadataKeySyncIdentifier: "\(id).\(field.suffix)",
                        HKMetadataKeySyncVersion: 1,
                        HKMetadataKeyFoodType: entry.name,
                    ]
                ))
            }
            entry.healthSyncID = id
        }
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    /// Removes the Health samples written for deleted entries. Pass the ids before deleting the models.
    func deleteFood(syncIDs: [String]) async {
        guard isOn, !syncIDs.isEmpty else { return }
        for field in Self.dietary where canWrite(field.type) {
            let ids = syncIDs.map { "\($0).\(field.suffix)" }
            _ = try? await store.deleteObjects(of: field.type, predicate: Self.syncPredicate(ids))
        }
    }

    // MARK: Weight

    func save(_ weight: WeightEntry) async {
        guard isOn, !weight.importedFromHealth, canWrite(Self.bodyMass) else { return }
        let id = weight.healthSyncID ?? UUID().uuidString
        let sample = HKQuantitySample(
            type: Self.bodyMass,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weight.kg),
            start: weight.date,
            end: weight.date,
            metadata: [HKMetadataKeySyncIdentifier: id, HKMetadataKeySyncVersion: 1]
        )
        weight.healthSyncID = id
        try? await store.save(sample)
    }

    func deleteWeight(syncIDs: [String]) async {
        guard isOn, !syncIDs.isEmpty, canWrite(Self.bodyMass) else { return }
        _ = try? await store.deleteObjects(of: Self.bodyMass, predicate: Self.syncPredicate(syncIDs))
    }

    /// Copies weigh-ins from other apps (e.g. a smart scale) that are newer than the
    /// latest local one. Keeps the profile weight current so the target follows it.
    func importWeights(into context: ModelContext) async {
        guard isOn else { return }
        var latest = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        let localLatest = (try? context.fetch(latest))?.first
        let since = localLatest?.date ?? Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate),
            NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default())),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: 500
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return }

        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: samples[0].startDate)
        var known = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.date >= firstDay }))) ?? []
        var newest: WeightEntry?
        for sample in samples {
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            let duplicate = known.contains {
                calendar.isDate($0.date, inSameDayAs: sample.startDate) && abs($0.kg - kg) < 0.05
            }
            guard !duplicate else { continue }
            let entry = WeightEntry(date: sample.startDate, kg: kg)
            entry.importedFromHealth = true
            context.insert(entry)
            known.append(entry)
            newest = entry
        }
        if let newest, newest.date > (localLatest?.date ?? .distantPast) {
            settings.profile.weightKg = (newest.kg * 10).rounded() / 10
        }
    }

    // MARK: Helpers

    private func canWrite(_ type: HKObjectType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    private static func syncPredicate(_ ids: [String]) -> NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ids)
    }
}
