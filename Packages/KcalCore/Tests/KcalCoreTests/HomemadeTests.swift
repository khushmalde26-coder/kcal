import Foundation
import Testing
@testable import KcalCore

@Suite("Homemade")
struct HomemadeTests {
    /// The bundled dataset, read from the app's resources.
    static let cofidNames: Set<String> = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kcal/Resources/cofid.json")
        let index = try! CoFIDIndex(json: Data(contentsOf: url))
        return Set(index.foods.map(\.name))
    }()

    @Test(arguments: StapleSlot.allCases)
    func fallbackExistsInCoFID(_ slot: StapleSlot) {
        #expect(Self.cofidNames.contains(slot.fallbackCoFIDName))
    }

    @Test func templateBasesExistInCoFID() {
        for template in HomemadeTemplate.all {
            for item in template.items {
                if case .generic(let name) = item.part {
                    #expect(Self.cofidNames.contains(name), "\(template.name): \(name)")
                }
            }
        }
    }

    @Test func recipeTotalsPerServingAndPer100() throws {
        let coffee = Nutrients(kcal: 2, protein: 0.2, carbs: 0.3, fat: 0)
        let milk = Nutrients(kcal: 46, protein: 3.5, carbs: 4.7, fat: 1.7, sugars: 4.7)
        let total = RecipeMath.total([(coffee, 200), (milk, 30)])
        #expect(abs(total.kcal - 17.8) < 0.001)
        #expect(abs(total.protein - 1.45) < 0.001)
        // Coffee has no sugars figure, milk does: the total keeps the known part.
        #expect(abs((total.sugars ?? 0) - 1.41) < 0.001)

        let half = RecipeMath.perServing(total, servings: 2)
        #expect(abs(half.kcal - 8.9) < 0.001)
        let per100 = try #require(RecipeMath.per100(total, totalGrams: 230))
        #expect(abs(per100.kcal - 7.739) < 0.001)
        #expect(RecipeMath.per100(total, totalGrams: 0) == nil)
    }

    @Test func breadSliceFollowsProductServing() {
        #expect(StapleSlot.bread.portions(servingGrams: 44).first?.grams == 44)
        #expect(StapleSlot.bread.portions().first?.grams == 36)
    }

    @Test func scannedProductsMatchSlots() {
        #expect(StapleSlot.match(productName: "Cravendale Semi Skimmed Milk") == .milk)
        #expect(StapleSlot.match(productName: "Oatly Oat Drink Barista") == .milk)
        #expect(StapleSlot.match(productName: "Lurpak Spreadable") == .butter)
        #expect(StapleSlot.match(productName: "Warburtons Toastie Bread") == .bread)
        #expect(StapleSlot.match(productName: "Dairy Milk Chocolate") == nil)
        #expect(StapleSlot.match(productName: "Baked beans") == nil)
    }
}
