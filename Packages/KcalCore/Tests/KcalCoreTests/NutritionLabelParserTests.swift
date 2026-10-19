import Testing
@testable import KcalCore

@Suite("Nutrition label parser")
struct NutritionLabelParserTests {

    @Test func ukLabelWithPer100AndPerServingColumns() throws {
        let label = NutritionLabelParser.parse(lines: [
            "Typical values Per 100g Per 15g serving",
            "Energy 2252kJ/539kcal 338kJ/81kcal",
            "Fat 30.9g 4.6g",
            "of which saturates 10.6g 1.6g",
            "Carbohydrate 57.5g 8.6g",
            "of which sugars 56.3g 8.4g",
            "Protein 6.3g 0.9g",
            "Salt 0.107g 0.016g",
        ])
        #expect(label.per100 == Nutrients(
            kcal: 539, protein: 6.3, carbs: 57.5, fat: 30.9,
            sugars: 56.3, saturatedFat: 10.6, salt: 0.107
        ))
        #expect(label.per100?.fibre == nil)
        #expect(label.perServing?.kcal == 81)
        #expect(label.perServing?.sugars == 8.4)
        #expect(label.perServing?.saturatedFat == 1.6)
        #expect(label.perServing?.salt == 0.016)
        #expect(label.servingGrams == 15)
        #expect(label.isLiquid == false)
        #expect(label.warnings.isEmpty)
    }

    @Test func usLabelPerServingOnly() throws {
        let label = NutritionLabelParser.parse(lines: [
            "Nutrition Facts",
            "8 servings per container",
            "Serving size 2/3 cup (55g)",
            "Amount per serving",
            "Calories 230",
            "% Daily Value*",
            "Total Fat 8g 10%",
            "Saturated Fat 1g 5%",
            "Trans Fat 0g",
            "Cholesterol 0mg 0%",
            "Sodium 160mg 7%",
            "Total Carbohydrate 37g 13%",
            "Dietary Fiber 4g 14%",
            "Total Sugars 12g",
            "Protein 3g",
            "*The % Daily Value tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.",
        ])
        #expect(label.per100 == nil)
        #expect(label.perServing == Nutrients(
            kcal: 230, protein: 3, carbs: 37, fat: 8,
            fibre: 4, sugars: 12, saturatedFat: 1, salt: 0.4
        ))
        #expect(label.servingGrams == 55)
        let per100 = try #require(label.resolvedPer100)
        #expect(abs(per100.kcal - 418.18) < 0.1)
        #expect(label.warnings.isEmpty)
    }

    @Test func drinkWithSlashPairsAndDecimalComma() {
        let label = NutritionLabelParser.parse(lines: [
            "Nutrition per 100ml",
            "Energy kJ/kcal 180/43",
            "Fat 0g",
            "Carbohydrate 10,6g",
            "Protein 0g",
        ])
        #expect(label.per100 == Nutrients(kcal: 43, protein: 0, carbs: 10.6, fat: 0))
        #expect(label.isLiquid)
        #expect(label.servingGrams == nil)
    }

    @Test func servingColumnBeforePer100Column() {
        let label = NutritionLabelParser.parse(lines: [
            "Per bar (40g) Per 100g",
            "Energy 180kcal 450kcal",
            "Fat 8g 20g",
            "Carbohydrate 20g 50g",
            "Protein 6g 15g",
        ])
        #expect(label.per100 == Nutrients(kcal: 450, protein: 15, carbs: 50, fat: 20))
        #expect(label.perServing == Nutrients(kcal: 180, protein: 6, carbs: 20, fat: 8))
        #expect(label.servingGrams == 40)
    }

    @Test func kilojoulesOnlyAreConverted() {
        let label = NutritionLabelParser.parse(lines: [
            "Average quantity per 100g",
            "Energy 1046 kJ",
            "Protein 9.0 g",
            "Fat, total 10.0 g",
            "Carbohydrate 30.0 g",
        ])
        #expect(label.per100?.kcal == 250)
        #expect(label.per100?.protein == 9)
    }

    @Test func ukDetailLinesWithFibreAndMonounsaturates() {
        let label = NutritionLabelParser.parse(lines: [
            "Per 100g",
            "Energy 1569kJ 374kcal",
            "Fat 8.0g",
            "of which saturates 1.5g",
            "mono-unsaturates 4.5g",
            "Carbohydrate 60g",
            "of which sugars 1.2g",
            "Fibre 9.0g",
            "Protein 11g",
            "Salt 0.01g",
        ])
        #expect(label.per100?.saturatedFat == 1.5)
        #expect(label.per100?.sugars == 1.2)
        #expect(label.per100?.fibre == 9)
        #expect(label.per100?.salt == 0.01)
    }

    @Test func usAddedSugarsDoNotReplaceTotalSugars() throws {
        let label = NutritionLabelParser.parse(lines: [
            "Serving size 1 bar (40g)",
            "Calories 190",
            "Total Fat 7g 9%",
            "Sodium 95mg 4%",
            "Total Carbohydrate 29g 11%",
            "Total Sugars 12g",
            "Includes 10g Added Sugars 20%",
            "Protein 3g",
        ])
        #expect(label.perServing?.sugars == 12)
        let salt = try #require(label.perServing?.salt)
        #expect(abs(salt - 0.2375) < 0.0001)
    }

    @Test func missingFieldsProduceWarnings() {
        let label = NutritionLabelParser.parse(lines: ["Per 100g", "Energy 400kcal"])
        #expect(label.per100?.kcal == 400)
        #expect(label.warnings.contains { $0.contains("protein") })
    }
}

@Suite("Text row grouping")
struct TextRowGrouperTests {
    @Test func joinsCellsOnTheSameLine() {
        let rows = TextRowGrouper.rows(from: [
            TextFragment(text: "6.3g", minX: 0.5, midY: 0.40, height: 0.03),
            TextFragment(text: "Protein", minX: 0.1, midY: 0.405, height: 0.03),
            TextFragment(text: "0.9g", minX: 0.8, midY: 0.398, height: 0.03),
            TextFragment(text: "Fat 30.9g", minX: 0.1, midY: 0.6, height: 0.03),
        ])
        #expect(rows == ["Fat 30.9g", "Protein 6.3g 0.9g"])
    }
}
