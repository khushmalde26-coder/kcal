import Foundation
import SwiftData
import KcalCore

/// A food the user has logged or saved. Values are stored per 100 g (or ml).
/// Every property has a default so the store can move to CloudKit sync later.
@Model
final class Food {
    var name: String = ""
    var brand: String?
    var barcode: String?
    var sourceRaw: String = FoodSource.custom.rawValue
    /// Remote id ("off:…", "fdc:…") so a re-searched food maps onto the saved one.
    var remoteID: String?
    var kcalPer100: Double = 0
    var proteinPer100: Double = 0
    var carbsPer100: Double = 0
    var fatPer100: Double = 0
    var servingGrams: Double?
    var servingLabel: String?
    var isLiquid: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.food)
    var entries: [LogEntry]? = []

    init(candidate: FoodCandidate) {
        name = candidate.name
        brand = candidate.brand
        barcode = candidate.barcode
        sourceRaw = candidate.source.rawValue
        remoteID = candidate.id
        kcalPer100 = candidate.per100.kcal
        proteinPer100 = candidate.per100.protein
        carbsPer100 = candidate.per100.carbs
        fatPer100 = candidate.per100.fat
        servingGrams = candidate.servingGrams
        servingLabel = candidate.servingLabel
        isLiquid = candidate.isLiquid
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .custom }

    var per100: Nutrients {
        get { Nutrients(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100) }
        set {
            kcalPer100 = newValue.kcal
            proteinPer100 = newValue.protein
            carbsPer100 = newValue.carbs
            fatPer100 = newValue.fat
        }
    }

    var unit: String { isLiquid ? "ml" : "g" }

    var subtitle: String {
        [brand, "\(Int(kcalPer100.rounded())) kcal per 100 \(unit)"].compactMap { $0 }.joined(separator: " · ")
    }

    var candidate: FoodCandidate {
        FoodCandidate(
            id: remoteID ?? "local:\(persistentModelID.hashValue)",
            name: name, brand: brand, barcode: barcode, per100: per100,
            servingGrams: servingGrams, servingLabel: servingLabel,
            isLiquid: isLiquid, source: source
        )
    }
}

/// One logged portion. Nutrients are copied at log time so editing or deleting
/// the food later never rewrites history.
@Model
final class LogEntry {
    var timestamp: Date = Date.now
    /// Start of the calendar day, for cheap day queries.
    var day: Date = Calendar.current.startOfDay(for: .now)
    var mealRaw: String = Meal.snacks.rawValue
    var grams: Double = 0
    var name: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var food: Food?

    init(food: Food, grams: Double, meal: Meal, date: Date) {
        self.food = food
        self.grams = grams
        self.mealRaw = meal.rawValue
        self.timestamp = date
        self.day = Calendar.current.startOfDay(for: date)
        self.name = food.name
        let n = food.per100.forPortion(grams: grams)
        self.kcal = n.kcal
        self.protein = n.protein
        self.carbs = n.carbs
        self.fat = n.fat
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snacks }
        set { mealRaw = newValue.rawValue }
    }

    var nutrients: Nutrients {
        get { Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }
}

@Model
final class WeightEntry {
    var date: Date = Date.now
    var kg: Double = 0

    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

enum Meal: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner, snacks

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snacks: "carrot"
        }
    }

    /// Best guess from the clock so most logs need no meal choice.
    static func suggested(for date: Date = .now) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snacks
        }
    }
}
