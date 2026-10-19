import Foundation

/// Energy and macronutrients. Grams for macros, kcal for energy.
public struct Nutrients: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = Nutrients()

    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }

    /// Nutrients for `grams` of a food whose values are given per 100 g.
    public func forPortion(grams: Double) -> Nutrients {
        scaled(by: grams / 100)
    }

    /// Energy implied by the macros (Atwater 4/4/9). Used to sanity check parsed labels.
    public var kcalFromMacros: Double {
        protein * 4 + carbs * 4 + fat * 9
    }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    public static func += (lhs: inout Nutrients, rhs: Nutrients) {
        lhs = lhs + rhs
    }
}

public enum FoodSource: String, Codable, CaseIterable, Sendable {
    case openFoodFacts
    case usda
    case label
    case custom
    case mealPhoto
}

/// A food found in a remote database or produced by a scan, before it is saved locally.
public struct FoodCandidate: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var per100: Nutrients
    public var servingGrams: Double?
    public var servingLabel: String?
    public var isLiquid: Bool
    public var source: FoodSource

    public init(
        id: String,
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        per100: Nutrients,
        servingGrams: Double? = nil,
        servingLabel: String? = nil,
        isLiquid: Bool = false,
        source: FoodSource
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.per100 = per100
        self.servingGrams = servingGrams
        self.servingLabel = servingLabel
        self.isLiquid = isLiquid
        self.source = source
    }
}
