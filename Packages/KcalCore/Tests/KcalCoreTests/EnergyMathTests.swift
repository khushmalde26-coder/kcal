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

    @Test func noActivityEarnsNothing() {
        let profile = EnergyProfile(sex: .female, age: 30, heightCm: 170, weightKg: 75, activity: .light, weeklyLossKg: 0.5)
        let target = EnergyMath.dailyTarget(profile, activeEnergyKcal: nil, activeCredit: 1)
        #expect(target == EnergyMath.dailyTarget(profile))
        #expect(target.baseKcal == 1510)
        #expect(target.earnedKcal == 0)
        #expect(target.totalKcal == 1510)
    }

    @Test func lowActivityDayKeepsBaseAndEarnsNothing() {
        // Light activity assumes 1501.5 x 0.275, about 413 kcal of movement.
        let profile = EnergyProfile(sex: .female, age: 30, heightCm: 170, weightKg: 75, activity: .light, weeklyLossKg: 0.5)
        for active in [0.0, 200, 550] {
            let target = EnergyMath.dailyTarget(profile, activeEnergyKcal: active, activeCredit: 0.75)
            #expect(target.baseKcal == 1510)
            #expect(target.earnedKcal == 0)
            #expect(target.totalKcal == 1510)
        }
    }

    @Test func bigActivityDayEarnsTheExcess() {
        let profile = EnergyProfile(sex: .female, age: 30, heightCm: 170, weightKg: 75, activity: .light, weeklyLossKg: 0.5)
        let target = EnergyMath.dailyTarget(profile, activeEnergyKcal: 1000, activeCredit: 0.75)
        // 750 credited minus about 412.9 already assumed by the light activity level.
        #expect(abs(target.earnedKcal - 337.09) < 0.01)
        #expect(target.baseKcal == 1510)
        #expect(abs(target.totalKcal - 1847.09) < 0.01)
        #expect(target.macros == EnergyMath.dailyTarget(profile).macros)
    }

    @Test func earnedIsAddedOnTopOfTheFloor() {
        let profile = EnergyProfile(sex: .female, age: 50, heightCm: 155, weightKg: 55, activity: .sedentary, weeklyLossKg: 1.0)
        let target = EnergyMath.dailyTarget(profile, activeEnergyKcal: 400, activeCredit: 1)
        // Sedentary assumes 1107.75 x 0.1, about 110.8 kcal.
        #expect(target.baseKcal == 1200)
        #expect(abs(target.earnedKcal - 289.225) < 0.01)
        #expect(target.adjustmentNote != nil)
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
        "countries_tags":["en:france","en:united-kingdom"],
        "nutriments":{"energy-kcal_100g":539,"proteins_100g":"6.3","carbohydrates_100g":57.5,"fat_100g":30.9}}}
        """
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: Data(json.utf8))
        let food = try #require(response.product?.candidate())
        #expect(food.name == "Nutella")
        #expect(food.brand == "Ferrero")
        #expect(food.per100 == Nutrients(kcal: 539, protein: 6.3, carbs: 57.5, fat: 30.9))
        #expect(food.countries == ["en:france", "en:united-kingdom"])
        #expect(food.servingGrams == 15)
        #expect(food.barcode == "3017624010701")
    }

    @Test func openFoodFactsDetailNutrientsAndSodiumFallback() throws {
        let json = """
        {"status":1,"product":{"code":"5000","product_name":"Oatcakes",
        "nutriments":{"energy-kcal_100g":450,"fiber_100g":8,"sugars_100g":"2.1",
        "saturated-fat_100g":4.2,"sodium_100g":0.4}}}
        """
        let response = try JSONDecoder().decode(OFFProductResponse.self, from: Data(json.utf8))
        let food = try #require(response.product?.candidate())
        #expect(food.per100.fibre == 8)
        #expect(food.per100.sugars == 2.1)
        #expect(food.per100.saturatedFat == 4.2)
        #expect(food.per100.salt == 1.0)
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
        {"nutrientNumber":"205","value":23.0},{"nutrientNumber":"204","value":0.29},
        {"nutrientNumber":"291","value":2.6},{"nutrientNumber":"269","value":15.8},{"nutrientNumber":"307","value":4}]}]}
        """
        let response = try JSONDecoder().decode(FDCSearchResponse.self, from: Data(json.utf8))
        let food = try #require(response.foods.first?.candidate())
        #expect(food.name == "Bananas, raw")
        #expect(food.per100.kcal == 97)
        #expect(food.source == .usda)
        #expect(food.per100.fibre == 2.6)
        #expect(food.per100.sugars == 15.8)
        #expect(food.per100.saturatedFat == nil)
        #expect(food.per100.salt == 0.01)
    }
}
