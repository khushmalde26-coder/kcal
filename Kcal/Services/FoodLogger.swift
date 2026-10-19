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
        // Log at the chosen day but the current time of day, so entries sort naturally.
        let time = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
        let timestamp = Calendar.current.date(
            bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date
        ) ?? date
        let entry = LogEntry(food: food, grams: grams, meal: meal, date: timestamp)
        insert(entry)
        return entry
    }
}
