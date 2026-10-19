import Foundation
import Testing
@testable import KcalCore

@Suite("Energy maths")
struct EnergyMathTests {

    @Test func typicalTarget() {
        let profile = EnergyProfile(sex: .female, age: 30, heightCm: 170, weightKg: 75, activity: .light, weeklyLossKg: 0.5)
        let target = EnergyMath.dailyTarget(profile)
        #expect(target.bmr == 1501.5)
        #expect(abs(target.maintenance - 2064.56) < 0.01)
        #expect(target.kcal == 1510)
        #expect(target.adjustmentNote == nil)
        #expect(target.macros.protein == 132)
    }

    @Test func aggressiveGoalIsCappedAndFloored() {
        let profile = EnergyProfile(sex: .female, age: 50, heightCm: 155, weightKg: 55, activity: .sedentary, weeklyLossKg: 1.0)
        let target = EnergyMath.dailyTarget(profile)
        #expect(target.kcal == 1200)
        #expect(target.plannedWeeklyLossKg < 0.2)
        #expect(target.adjustmentNote != nil)
    }

    @Test func noActiveEnergyKeepsMultiplierTarget() {
        let profile = EnergyProfile(sex: .female, age: 30, heightCm: 170, weightKg: 75, activity: .light, weeklyLossKg: 0.5)
        let target = EnergyMath.dailyTarget(profile, activeEnergyKcal: nil, activeCredit: 0.5)
        #expect(target == EnergyMath.dailyTarget(profile))
        #expect(target.kcal == 1510)
        #expect(target.activityKcal == nil)
    }

    @Test func activeEnergyIsCreditedOnTopOfRestingPlusFood() {
        // BMR 1880, so resting plus food is 2068 and the 0.5 kg deficit leaves about 1518.
        let profile = EnergyProfile(sex: .male, age: 30, heightCm: 180, weightKg: 90, activity: .veryActive, weeklyLossKg: 0.5)
        let rest = EnergyMath.dailyTarget(profile, activeEnergyKcal: 0, activeCredit: 0.75)
        let active = EnergyMath.dailyTarget(profile, activeEnergyKcal: 400, activeCredit: 0.75)
        #expect(abs(rest.maintenance - 2068) < 0.01)
        #expect(rest.kcal == 1520)
        #expect(active.activityKcal == 300)
        #expect(abs(active.maintenance - rest.maintenance - 300) < 0.01)
        #expect(active.kcal - rest.kcal == 300)
        #expect(active.adjustmentNote == nil)
    }

    @Test func floorStillAppliesWithActiveEnergy() {
        // 1501.5 x 1.1 minus a 550 kcal deficit is about 1102, below the 1200 floor.
        let profile = EnergyProfile(sex: .female, age: 30, heightCm: 170, weightKg: 75, activity: .light, weeklyLossKg: 0.5)
        let target = EnergyMath.dailyTarget(profile, activeEnergyKcal: 0, activeCredit: 0.75)
        #expect(target.kcal == 1200)
        #expect(target.adjustmentNote != nil)
        #expect(target.plannedWeeklyLossKg < 0.5)
    }

    @Test func trendSmoothsNoise() {
        let trend = EnergyMath.trend([80, 81, 79, 80])
        #expect(trend.first == 80)
        #expect(trend.allSatisfy { abs($0 - 80) < 0.2 })
    }
}

@Suite("Food database decoding")
struct FoodDatabaseDecodingTests {

    @Test func openFoodFactsProductWithStringNumbers() throws {
        let json = """
        {"status":1,"product":{"code":"3017624010701","product_name":"Nutella","brands":"Ferrero, Nutella",
        "serving_size":"15 g","serving_quantity":"15","product_quantity_unit":"g",
        "nutriments":{"energy-kcal_100g":539,"proteins_100g":"6.3","carbohydrates_100g":57.5,"fat_100g":30.9}}}
        """
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: Data(json.utf8))
        let food = try #require(response.product?.candidate())
        #expect(food.name == "Nutella")
        #expect(food.brand == "Ferrero")
        #expect(food.per100 == Nutrients(kcal: 539, protein: 6.3, carbs: 57.5, fat: 30.9))
        #expect(food.servingGrams == 15)
        #expect(food.barcode == "3017624010701")
    }

    @Test func productWithoutEnergyIsDropped() throws {
        let json = #"{"status":1,"product":{"code":"1","product_name":"Mystery","nutriments":{}}}"#
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: Data(json.utf8))
        #expect(response.product?.candidate() == nil)
    }

    @Test func usdaFoundationFoodUsesAtwaterEnergy() throws {
        let json = """
        {"foods":[{"fdcId":1105314,"description":"BANANAS, RAW","foodNutrients":[
        {"nutrientNumber":"958","value":97},{"nutrientNumber":"203","value":0.74},
        {"nutrientNumber":"205","value":23.0},{"nutrientNumber":"204","value":0.29}]}]}
        """
        let response = try JSONDecoder().decode(FDCSearchResponse.self, from: Data(json.utf8))
        let food = try #require(response.foods.first?.candidate())
        #expect(food.name == "Bananas, raw")
        #expect(food.per100.kcal == 97)
        #expect(food.source == .usda)
    }
}
