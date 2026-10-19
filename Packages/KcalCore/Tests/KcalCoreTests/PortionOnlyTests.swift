import Testing
@testable import KcalCore

@Suite("Portion-only foods")
struct PortionOnlyTests {
    /// A homemade flapjack entered from its per-portion label, no weight.
    let flapjack = FoodCandidate(
        id: "custom:flapjack", name: "Flapjack",
        per100: Nutrients(kcal: 210, protein: 3, carbs: 28, fat: 9, sugars: 14),
        source: .custom, isPerPortion: true
    )

    @Test func scalesByPortions() {
        let oneAndAHalf = flapjack.per100.forPortion(grams: Amount.units(portions: 1.5))
        #expect(oneAndAHalf.kcal == 315)
        #expect(oneAndAHalf.sugars == 21)
        #expect(Amount.portions(units: 150) == 1.5)
    }

    @Test func amountsReadAsPortions() {
        #expect(flapjack.amountText(100) == "1 portion")
        #expect(flapjack.amountText(150) == "1.5 portions")
        #expect(flapjack.unit == "portion")
        #expect(flapjack.basisLabel == "per portion")
    }

    @Test func weighedFoodsAreUnchanged() {
        let milk = FoodCandidate(id: "m", name: "Milk", per100: Nutrients(kcal: 46), isLiquid: true, source: .cofid)
        #expect(!milk.isPerPortion)
        #expect(milk.amountText(30) == "30 ml")
        #expect(milk.basisLabel == "per 100 ml")
    }

    @Test func recipeMixesWeighedAndPortionOnlyIngredients() {
        let yoghurt = Nutrients(kcal: 79, protein: 5.7, carbs: 7.8, fat: 3)
        // 150 g yoghurt plus 2 flapjacks.
        let total = RecipeMath.total([(yoghurt, 150), (flapjack.per100, Amount.units(portions: 2))])
        #expect(abs(total.kcal - 538.5) < 0.001)
        #expect(abs(total.protein - 14.55) < 0.001)
        // Sugars are only known for the flapjack, so the total keeps that part.
        #expect(total.sugars == 28)
    }
}
