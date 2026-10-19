import Foundation
import SwiftData
import KcalCore

/// The user's staple products, read from a @Query so views update when one changes.
struct StapleBook {
    let choices: [StapleChoice]

    func food(for slot: StapleSlot) -> Food? {
        choices.first { $0.slot == slot }?.food
    }

    /// The chosen product, or the generic UK food until one is chosen.
    func candidate(for slot: StapleSlot) -> FoodCandidate? {
        food(for: slot)?.candidate ?? FoodDatabase.cofidCandidate(named: slot.fallbackCoFIDName)
    }

    func isDefault(_ slot: StapleSlot) -> Bool { food(for: slot) == nil }
}

/// An ingredient with real values, ready to total up.
struct ResolvedIngredient: Identifiable {
    var id: UUID = UUID()
    var name: String
    var per100: Nutrients
    var grams: Double
    var unitLabel: String?
    var isLiquid: Bool
    var slot: StapleSlot?

    var unit: String { isLiquid ? "ml" : "g" }
    var portion: Nutrients { per100.forPortion(grams: grams) }

    /// "Semi-skimmed milk · 30 ml (splash)"
    func note(scale: Double = 1) -> String {
        "\(name) · \(amountText(scale: scale))"
    }

    /// "30 ml (splash)"
    func amountText(scale: Double = 1) -> String {
        let amount = (grams * scale).formatted(.number.precision(.fractionLength(0...1)))
        let label = unitLabel.map { " (\($0.lowercased()))" } ?? ""
        return "\(amount) \(unit)\(label)"
    }
}

/// An ingredient being edited: a staple slot or a specific food, plus an amount.
struct IngredientDraft: Identifiable {
    var id = UUID()
    var slot: StapleSlot?
    var food: Food?
    /// A generic base from CoFID that isn't saved as a Food until the recipe is.
    var generic: FoodCandidate?
    var grams: Double
    var unitLabel: String?
    var question: String?
    var portions: [PortionChoice] = []
    var isOptional = false

    init(slot: StapleSlot? = nil, food: Food? = nil, generic: FoodCandidate? = nil, grams: Double,
         unitLabel: String? = nil, question: String? = nil, portions: [PortionChoice] = [], isOptional: Bool = false) {
        self.slot = slot
        self.food = food
        self.generic = generic
        self.grams = grams
        self.unitLabel = unitLabel
        self.question = question
        self.portions = portions
        self.isOptional = isOptional
    }

    init(_ ingredient: RecipeIngredient) {
        slot = ingredient.slot
        food = ingredient.food
        grams = ingredient.grams
        unitLabel = ingredient.unitLabel
    }

    func resolve(with staples: StapleBook) -> ResolvedIngredient? {
        let candidate = slot.flatMap { staples.candidate(for: $0) } ?? food?.candidate ?? generic
        guard let candidate else { return nil }
        return ResolvedIngredient(
            name: candidate.name, per100: candidate.per100, grams: grams, unitLabel: unitLabel,
            isLiquid: candidate.isLiquid || (slot?.isLiquid ?? false), slot: slot
        )
    }

    /// Chips for this ingredient: the template's, else the slot's.
    func choices(with staples: StapleBook) -> [PortionChoice] {
        if !portions.isEmpty { return portions }
        guard let slot else { return [] }
        return slot.portions(servingGrams: staples.food(for: slot)?.servingGrams)
    }
}

extension ModelContext {
    func setStaple(_ slot: StapleSlot, food: Food?) {
        let raw = slot.rawValue
        let existing = (try? fetch(FetchDescriptor<StapleChoice>(predicate: #Predicate { $0.slotRaw == raw }))) ?? []
        if let choice = existing.first {
            choice.food = food
            existing.dropFirst().forEach(delete)
        } else {
            insert(StapleChoice(slot: slot, food: food))
        }
    }

    /// Replaces the recipe's ingredients with the drafts. Generic bases are saved as foods.
    func save(_ drafts: [IngredientDraft], into recipe: Recipe) {
        recipe.ingredients?.forEach(delete)
        recipe.ingredients = []
        for (order, draft) in drafts.enumerated() where !(draft.isOptional && draft.grams <= 0) {
            let fixed = draft.slot == nil ? (draft.food ?? draft.generic.map(food(for:))) : nil
            let ingredient = RecipeIngredient(order: order, slot: draft.slot, food: fixed, grams: draft.grams, unitLabel: draft.unitLabel)
            insert(ingredient)
            recipe.ingredients?.append(ingredient)
        }
    }
}
