import Foundation
import SwiftData
import KcalCore

/// Saving foods and portions. Keeps one local `Food` per product so recents,
/// favourites and barcode lookups all point at the same record.
extension ModelContext {

    func food(for candidate: FoodCandidate) -> Food {
        if let existing = existingFood(remoteID: candidate.id, barcode: candidate.barcode) {
            return existing
        }
        let food = Food(candidate: candidate)
        insert(food)
        return food
    }

    func existingFood(remoteID: String? = nil, barcode: String? = nil) -> Food? {
        if let barcode, !barcode.isEmpty {
            let code: String? = barcode
            let byBarcode = FetchDescriptor<Food>(predicate: #Predicate { $0.barcode == code })
            if let match = try? fetch(byBarcode).first { return match }
        }
        if let remoteID {
            let id: String? = remoteID
            let byID = FetchDescriptor<Food>(predicate: #Predicate { $0.remoteID == id })
            if let match = try? fetch(byID).first { return match }
        }
        return nil
    }

    @discardableResult
    func log(_ food: Food, grams: Double, meal: Meal, on date: Date) -> LogEntry {
        food.lastUsedAt = .now
        let entry = LogEntry(food: food, grams: grams, meal: meal, date: Self.logTime(on: date))
        insert(entry)
        return entry
    }

    @discardableResult
    func quickAdd(name: String, kcal: Double, meal: Meal, on date: Date) -> LogEntry {
        let entry = LogEntry(quickAdd: name, kcal: kcal, meal: meal, date: Self.logTime(on: date))
        insert(entry)
        return entry
    }

    /// The chosen day at the current time of day, so entries sort naturally.
    private static func logTime(on date: Date) -> Date {
        let time = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
        return Calendar.current.date(
            bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date
        ) ?? date
    }
}
