import Foundation

// MARK: - Open Food Facts (barcodes, branded products)
// https://openfoodfacts.github.io/openfoodfacts-server/api/

public struct OFFProductResponse: Decodable, Sendable {
    public var status: Int?
    public var product: OFFProduct?
}

public struct OFFSearchResponse: Decodable, Sendable {
    public var products: [OFFProduct]
}

public struct OFFProduct: Decodable, Sendable {
    public var code: String?
    public var productName: String?
    public var brands: String?
    public var servingSize: String?
    public var servingQuantity: Double?
    public var quantityUnit: String?
    public var nutriments: OFFNutriments?

    /// Fields to request, keeps responses small.
    public static let fields = "code,product_name,brands,serving_size,serving_quantity,product_quantity_unit,nutriments"

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case quantityUnit = "product_quantity_unit"
        case nutriments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        productName = try? c.decodeIfPresent(String.self, forKey: .productName)
        brands = try? c.decodeIfPresent(String.self, forKey: .brands)
        servingSize = try? c.decodeIfPresent(String.self, forKey: .servingSize)
        servingQuantity = c.lossyDouble(.servingQuantity)
        quantityUnit = try? c.decodeIfPresent(String.self, forKey: .quantityUnit)
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
    }

    /// Nil when the product has no name or no energy value, which is common in
    /// crowd-sourced data and useless for logging.
    public func candidate() -> FoodCandidate? {
        guard let name = productName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let n = nutriments, let kcal = n.kcal100 ?? n.kj100.map({ $0 / 4.184 })
        else { return nil }
        let brand = brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return FoodCandidate(
            id: "off:\(code ?? name)",
            name: name,
            brand: brand,
            barcode: code,
            per100: Nutrients(kcal: kcal, protein: n.protein100 ?? 0, carbs: n.carbs100 ?? 0, fat: n.fat100 ?? 0),
            servingGrams: servingQuantity.flatMap { $0 > 0 ? $0 : nil },
            servingLabel: servingSize,
            isLiquid: quantityUnit?.lowercased() == "ml" || quantityUnit?.lowercased() == "l",
            source: .openFoodFacts
        )
    }
}

public struct OFFNutriments: Decodable, Sendable {
    public var kcal100: Double?
    public var kj100: Double?
    public var protein100: Double?
    public var carbs100: Double?
    public var fat100: Double?

    enum CodingKeys: String, CodingKey {
        case kcal100 = "energy-kcal_100g"
        case kj100 = "energy-kj_100g"
        case protein100 = "proteins_100g"
        case carbs100 = "carbohydrates_100g"
        case fat100 = "fat_100g"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kcal100 = c.lossyDouble(.kcal100)
        kj100 = c.lossyDouble(.kj100)
        protein100 = c.lossyDouble(.protein100)
        carbs100 = c.lossyDouble(.carbs100)
        fat100 = c.lossyDouble(.fat100)
    }
}

// MARK: - USDA FoodData Central (generic foods like "banana", "chicken breast")
// https://fdc.nal.usda.gov/api-guide

public struct FDCSearchResponse: Decodable, Sendable {
    public var foods: [FDCFood]
}

public struct FDCFood: Decodable, Sendable {
    public var fdcId: Int
    public var description: String
    public var brandOwner: String?
    public var foodNutrients: [FDCNutrient]

    public func candidate() -> FoodCandidate? {
        func value(_ numbers: String...) -> Double? {
            for number in numbers {
                if let v = foodNutrients.first(where: { $0.nutrientNumber == number })?.value { return v }
            }
            return nil
        }
        // 208 = Energy (kcal); Foundation foods often only have the Atwater variants 958/957.
        guard let kcal = value("208", "958", "957") ?? value("268").map({ $0 / 4.184 }) else { return nil }
        return FoodCandidate(
            id: "fdc:\(fdcId)",
            name: Self.tidy(description),
            brand: brandOwner,
            per100: Nutrients(kcal: kcal, protein: value("203") ?? 0, carbs: value("205") ?? 0, fat: value("204") ?? 0),
            source: .usda
        )
    }

    /// "BANANAS, RAW" and "Bananas, raw" both become "Bananas, raw".
    static func tidy(_ s: String) -> String {
        let lower = s.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

public struct FDCNutrient: Decodable, Sendable {
    public var nutrientNumber: String?
    public var value: Double?
}

// MARK: - Helpers

extension KeyedDecodingContainer {
    /// Open Food Facts mixes numbers and numeric strings for the same field.
    func lossyDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}
