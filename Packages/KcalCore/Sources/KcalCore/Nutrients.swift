import Foundation

/// Energy and macronutrients. Grams for macros, kcal for energy.
/// Fibre, sugars, saturated fat and salt are optional: nil means the source didn't say,
/// which is different from zero.
public struct Nutrients: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double?
    public var sugars: Double?
    public var saturatedFat: Double?
    public var salt: Double?

    public init(
        kcal: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        fibre: Double? = nil,
        sugars: Double? = nil,
        saturatedFat: Double? = nil,
        salt: Double? = nil
    ) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fibre = fibre
        self.sugars = sugars
        self.saturatedFat = saturatedFat
        self.salt = salt
    }

    public static let zero = Nutrients()

    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
            fibre: fibre.map { $0 * factor }, sugars: sugars.map { $0 * factor },
            saturatedFat: saturatedFat.map { $0 * factor }, salt: salt.map { $0 * factor }
        )
    }

    /// Salt equivalent of sodium, as UK and EU labels state it.
    public static func salt(fromSodiumGrams sodium: Double) -> Double {
        sodium * 2.5
    }

    /// Nutrients for `grams` of a food whose values are given per 100 g.
    public func forPortion(grams: Double) -> Nutrients {
        scaled(by: grams / 100)
    }

    /// Energy implied by the macros (Atwater 4/4/9). Used to sanity check parsed labels.
    public var kcalFromMacros: Double {
        protein * 4 + carbs * 4 + fat * 9
    }

    /// Optional nutrients add up when either side has a value; nil only when both are unknown.
    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        func add(_ a: Double?, _ b: Double?) -> Double? {
            a == nil && b == nil ? nil : (a ?? 0) + (b ?? 0)
        }
        return Nutrients(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fibre: add(lhs.fibre, rhs.fibre),
            sugars: add(lhs.sugars, rhs.sugars),
            saturatedFat: add(lhs.saturatedFat, rhs.saturatedFat),
            salt: add(lhs.salt, rhs.salt)
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
    case cofid
    case quickAdd

    public var label: String {
        switch self {
        case .openFoodFacts: "Open Food Facts"
        case .usda: "USDA FoodData Central"
        case .label: "Your label scan"
        case .custom: "Your food"
        case .mealPhoto: "Meal photo estimate"
        case .cofid: "McCance and Widdowson's (UK)"
        case .quickAdd: "Quick add"
        }
    }
}

/// Amounts are stored in grams (or ml). Portion-only foods, entered from a label or by
/// hand without a weight, have no grams: their values are per 1 portion and their
/// amounts are counted in portions, stored as 100 units per portion so the same
/// "per 100" maths works for both.
public enum Amount {
    public static let unitsPerPortion = 100.0

    /// Stored amount for a number of portions of a portion-only food.
    public static func units(portions: Double) -> Double { portions * unitsPerPortion }

    public static func portions(units: Double) -> Double { units / unitsPerPortion }

    /// "250 g", "200 ml", "1 portion", "1.5 portions".
    public static func text(_ amount: Double, isPerPortion: Bool, isLiquid: Bool) -> String {
        if isPerPortion {
            let n = portions(units: amount)
            return "\(n.formatted(.number.precision(.fractionLength(0...2)))) portion\(n == 1 ? "" : "s")"
        }
        return "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(isLiquid ? "ml" : "g")"
    }
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
    /// Open Food Facts country tags, e.g. "en:united-kingdom". Empty for other sources.
    public var countries: [String]
    /// Values are per 1 portion (no weight known), not per 100 g. See `Amount`.
    public var isPerPortion: Bool

    /// "g", "ml" or "portion".
    public var unit: String { isPerPortion ? "portion" : (isLiquid ? "ml" : "g") }
    /// "per 100 g", "per 100 ml" or "per portion".
    public var basisLabel: String { isPerPortion ? "per portion" : "per 100 \(unit)" }

    public func amountText(_ amount: Double) -> String {
        Amount.text(amount, isPerPortion: isPerPortion, isLiquid: isLiquid)
    }

    public init(
        id: String,
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        per100: Nutrients,
        servingGrams: Double? = nil,
        servingLabel: String? = nil,
        isLiquid: Bool = false,
        source: FoodSource,
        countries: [String] = [],
        isPerPortion: Bool = false
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
        self.countries = countries
        self.isPerPortion = isPerPortion
    }
}
