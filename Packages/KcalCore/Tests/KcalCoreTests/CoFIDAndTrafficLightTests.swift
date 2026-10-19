import Foundation
import Testing
@testable import KcalCore

@Suite("CoFID search")
struct CoFIDTests {
    let index = try! CoFIDIndex(json: Data("""
    [{"i":"14-347","n":"Bananas, raw, flesh only, weighed with skin","k":51,"p":0.8,"c":12.8,"f":0,"s":11.4},
     {"i":"14-318","n":"Bananas, flesh only","k":81,"p":1.2,"c":20.3,"f":0.1,"fi":1.4,"s":18.1,"sf":0,"sa":0},
     {"i":"11-1029","n":"Banana bread, homemade","k":331,"p":4.4,"c":53.9,"f":12.4},
     {"i":"13-1","n":"Chicken, breast, grilled, without skin","k":148,"p":32,"c":0,"f":2.2},
     {"i":"17-506","n":"Beer, bitter, average","k":30,"p":0.3,"c":2.2,"f":0,"l":1}]
    """.utf8))

    @Test func prefixWordsMatchAndGenericComesFirst() {
        let results = index.search("banana")
        #expect(results.map(\.name) == [
            "Bananas, flesh only",
            "Banana bread, homemade",
            "Bananas, raw, flesh only, weighed with skin",
        ])
        let banana = results[0]
        #expect(banana.id == "cofid:14-318")
        #expect(banana.source == .cofid)
        #expect(banana.per100.fibre == 1.4)
        #expect(banana.per100.salt == 0)
    }

    @Test func everyTermMustMatchAWordStart() {
        #expect(index.search("chick bre").map(\.name) == ["Chicken, breast, grilled, without skin"])
        #expect(index.search("hicken").isEmpty)
        #expect(index.search("   ").isEmpty)
    }

    @Test func alcoholicDrinksAreLiquid() {
        #expect(index.search("beer").first?.isLiquid == true)
    }
}

@Suite("Traffic lights")
struct TrafficLightTests {
    @Test func foodThresholds() {
        #expect(TrafficLight.rating(.sugars, per100: 5, isLiquid: false) == .low)
        #expect(TrafficLight.rating(.sugars, per100: 5.1, isLiquid: false) == .medium)
        #expect(TrafficLight.rating(.sugars, per100: 22.6, isLiquid: false) == .high)
        #expect(TrafficLight.rating(.saturatedFat, per100: 5, isLiquid: false) == .medium)
        #expect(TrafficLight.rating(.salt, per100: 1.6, isLiquid: false) == .high)
        #expect(TrafficLight.rating(.fat, per100: 3, isLiquid: false) == .low)
    }

    @Test func drinksUseHalvedThresholds() {
        #expect(TrafficLight.rating(.sugars, per100: 10.6, isLiquid: true) == .medium)
        #expect(TrafficLight.rating(.sugars, per100: 11.3, isLiquid: true) == .high)
        #expect(TrafficLight.rating(.salt, per100: 0.8, isLiquid: true) == .high)
    }
}
