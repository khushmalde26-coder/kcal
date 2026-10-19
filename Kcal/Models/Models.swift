import Foundation
import SwiftData
import KcalCore

/// A food the user has logged or saved. Values are stored per 100 g (or ml), or per
/// portion for portion-only foods (`isPerPortion`, see `Amount` in KcalCore).
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
    var fibrePer100: Double?
    var sugarsPer100: Double?
    var saturatedFatPer100: Double?
    var saltPer100: Double?
    var servingGrams: Double?
    var servingLabel: String?
    var isLiquid: Bool = false
    /// Values are per 1 portion, entered without a weight. Amounts count portions.
    var isPerPortion: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.food)
    var entries: [LogEntry]? = []
    @Relationship(deleteRule: .nullify, inverse: \RecipeIngredient.food)
    var recipeUses: [RecipeIngredient]? = []
    @Relationship(deleteRule: .nullify, inverse: \StapleChoice.food)
    var stapleChoices: [StapleChoice]? = []

    init(candidate: FoodCandidate) {
        sourceRaw = candidate.source.rawValue
        remoteID = candidate.id
        update(from: candidate)
    }

    /// Copies the editable details; source and id stay as they were.
    func update(from candidate: FoodCandidate) {
        name = candidate.name
        brand = candidate.brand
        barcode = candidate.barcode
        per100 = candidate.per100
        servingGrams = candidate.servingGrams
        servingLabel = candidate.servingLabel
        isLiquid = candidate.isLiquid
        isPerPortion = candidate.isPerPortion
    }

    /// Foods the user entered themselves, by hand or from a label photo.
    var isUserCreated: Bool { source == .custom || source == .label }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .custom }

    var per100: Nutrients {
        get {
            Nutrients(
                kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100,
                fibre: fibrePer100, sugars: sugarsPer100, saturatedFat: saturatedFatPer100, salt: saltPer100
            )
        }
        set {
            kcalPer100 = newValue.kcal
            proteinPer100 = newValue.protein
            carbsPer100 = newValue.carbs
            fatPer100 = newValue.fat
            fibrePer100 = newValue.fibre
            sugarsPer100 = newValue.sugars
            saturatedFatPer100 = newValue.saturatedFat
            saltPer100 = newValue.salt
        }
    }

    var unit: String { candidate.unit }

    var subtitle: String {
        [brand, "\(Int(kcalPer100.rounded())) kcal \(candidate.basisLabel)"].compactMap { $0 }.joined(separator: " · ")
    }

    var candidate: FoodCandidate {
        FoodCandidate(
            id: remoteID ?? "local:\(persistentModelID.hashValue)",
            name: name, brand: brand, barcode: barcode, per100: per100,
            servingGrams: servingGrams, servingLabel: servingLabel,
            isLiquid: isLiquid, source: source, isPerPortion: isPerPortion
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
    var fibre: Double?
    var sugars: Double?
    var saturatedFat: Double?
    var salt: Double?
    var food: Food?
    /// Set for homemade items; the values are a snapshot, so editing the recipe later
    /// doesn't change what was logged.
    var recipe: Recipe?
    /// "Semi-skimmed milk, 30 ml" lines for homemade items, as logged.
    var ingredientNotes: [String] = []
    /// Base sync identifier of the samples written to Apple Health, if any.
    var healthSyncID: String?
    /// Bumped when the entry is edited so Health replaces the old samples.
    var healthSyncVersion: Int = 1

    init(food: Food, grams: Double, meal: Meal, date: Date) {
        self.food = food
        self.mealRaw = meal.rawValue
        self.timestamp = date
        self.day = Calendar.current.startOfDay(for: date)
        self.name = food.name
        setPortion(grams: grams)
    }

    /// A one-off calorie number with no food behind it, optionally with macros.
    init(quickAdd name: String, nutrients: Nutrients, meal: Meal, date: Date) {
        self.name = name
        self.mealRaw = meal.rawValue
        self.timestamp = date
        self.day = Calendar.current.startOfDay(for: date)
        self.nutrients = nutrients
    }

    /// A homemade item, with its ingredients resolved at log time.
    init(recipe: Recipe, nutrients: Nutrients, grams: Double, notes: [String], meal: Meal, date: Date) {
        self.recipe = recipe
        self.name = recipe.name
        self.grams = grams
        self.ingredientNotes = notes
        self.mealRaw = meal.rawValue
        self.timestamp = date
        self.day = Calendar.current.startOfDay(for: date)
        self.nutrients = nutrients
    }

    var isQuickAdd: Bool { food == nil && grams == 0 }

    /// Changes the amount and recomputes the snapshot from the food, or by scaling
    /// the old values if the food has since been deleted.
    func setPortion(grams newGrams: Double) {
        if let food {
            nutrients = food.per100.forPortion(grams: newGrams)
        } else if grams > 0 {
            nutrients = nutrients.scaled(by: newGrams / grams)
        }
        grams = newGrams
    }

    /// "250 g" or "1.5 portions".
    var amountText: String {
        Amount.text(grams, isPerPortion: food?.isPerPortion ?? false, isLiquid: food?.isLiquid ?? false)
    }

    var isPerPortion: Bool { food?.isPerPortion ?? false }

    /// Values per 100 g (or ml), or per portion for portion-only foods, as logged.
    var per100: Nutrients? {
        if let food { return food.per100 }
        return grams > 0 ? nutrients.scaled(by: 100 / grams) : nil
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snacks }
        set { mealRaw = newValue.rawValue }
    }

    var nutrients: Nutrients {
        get {
            Nutrients(
                kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                fibre: fibre, sugars: sugars, saturatedFat: saturatedFat, salt: salt
            )
        }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
            fibre = newValue.fibre
            sugars = newValue.sugars
            saturatedFat = newValue.saturatedFat
            salt = newValue.salt
        }
    }
}

@Model
final class WeightEntry {
    var date: Date = Date.now
    var kg: Double = 0
    /// Sync identifier of the sample Kcal wrote to Apple Health, if any.
    var healthSyncID: String?
    /// Read from Apple Health (another app or a scale), so never written back.
    var importedFromHealth: Bool = false

    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// The user's own product for a staple slot (their milk, their bread).
@Model
final class StapleChoice {
    var slotRaw: String = ""
    var food: Food?

    init(slot: StapleSlot, food: Food?) {
        slotRaw = slot.rawValue
        self.food = food
    }

    var slot: StapleSlot? { StapleSlot(rawValue: slotRaw) }
}

/// A homemade item built from staples and foods, e.g. "My morning coffee".
@Model
final class Recipe {
    var name: String = ""
    var symbol: String = "fork.knife"
    /// How many servings the ingredients make. Logging uses one serving by default.
    var servings: Double = 1
    var templateID: String?
    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now
    var useCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]? = []
    @Relationship(deleteRule: .nullify, inverse: \LogEntry.recipe)
    var entries: [LogEntry]? = []

    init(name: String, symbol: String, servings: Double = 1, templateID: String? = nil) {
        self.name = name
        self.symbol = symbol
        self.servings = servings
        self.templateID = templateID
    }

    var sortedIngredients: [RecipeIngredient] {
        (ingredients ?? []).sorted { $0.order < $1.order }
    }
}

/// Either a staple slot (resolved to the current default when logging) or a fixed food.
@Model
final class RecipeIngredient {
    var order: Int = 0
    var slotRaw: String?
    var food: Food?
    var grams: Double = 0
    var unitLabel: String?
    var recipe: Recipe?

    init(order: Int, slot: StapleSlot?, food: Food?, grams: Double, unitLabel: String?) {
        self.order = order
        self.slotRaw = slot?.rawValue
        self.food = food
        self.grams = grams
        self.unitLabel = unitLabel
    }

    var slot: StapleSlot? { slotRaw.flatMap(StapleSlot.init(rawValue:)) }
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
