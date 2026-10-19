import Foundation

/// McCance and Widdowson's Composition of Foods Integrated Dataset (UK generic foods),
/// bundled as JSON by scripts/build_cofid.py. Values per 100 g, or per 100 ml for drinks.
public struct CoFIDFood: Decodable, Sendable {
    public var id: String
    public var name: String
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fibre: Double?
    public var sugars: Double?
    public var saturatedFat: Double?
    public var salt: Double?
    public var isLiquid: Bool

    enum CodingKeys: String, CodingKey {
        case id = "i", name = "n", kcal = "k", protein = "p", carbs = "c", fat = "f"
        case fibre = "fi", sugars = "s", saturatedFat = "sf", salt = "sa", liquid = "l"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kcal = try c.decode(Double.self, forKey: .kcal)
        protein = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fat = try c.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        fibre = try c.decodeIfPresent(Double.self, forKey: .fibre)
        sugars = try c.decodeIfPresent(Double.self, forKey: .sugars)
        saturatedFat = try c.decodeIfPresent(Double.self, forKey: .saturatedFat)
        salt = try c.decodeIfPresent(Double.self, forKey: .salt)
        isLiquid = try c.decodeIfPresent(Int.self, forKey: .liquid) == 1
    }

    public var candidate: FoodCandidate {
        FoodCandidate(
            id: "cofid:\(id)",
            name: name,
            per100: Nutrients(
                kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                fibre: fibre, sugars: sugars, saturatedFat: saturatedFat, salt: salt
            ),
            isLiquid: isLiquid,
            source: .cofid
        )
    }
}

/// In-memory search over CoFID. About 2,900 foods, so a linear scan is instant.
public struct CoFIDIndex: Sendable {
    public let foods: [CoFIDFood]
    private let names: [String]

    public init(foods: [CoFIDFood]) {
        self.foods = foods
        names = foods.map { Self.fold($0.name) }
    }

    public init(json: Data) throws {
        self.init(foods: try JSONDecoder().decode([CoFIDFood].self, from: json))
    }

    /// Every word of the query must start a word in the name ("chick bre" finds
    /// "Chicken, breast, grilled"). Names that start with the first word come first,
    /// then shorter (more generic) names. "Weighed with skin/bone" variants go last.
    public func search(_ query: String, limit: Int = 25) -> [FoodCandidate] {
        let terms = Self.fold(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !terms.isEmpty else { return [] }

        var matches: [(index: Int, score: Int)] = []
        for (i, name) in names.enumerated() {
            let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard terms.allSatisfy({ term in words.contains { $0.hasPrefix(term) } }) else { continue }
            var score = name.count
            if words.first?.hasPrefix(terms[0]) == true { score -= 1000 }
            if name.contains("weighed with") { score += 2000 }
            matches.append((i, score))
        }
        return matches
            .sorted { $0.score < $1.score }
            .prefix(limit)
            .map { foods[$0.index].candidate }
    }

    /// Exact name lookup, for staple fallbacks and template bases.
    public func food(named name: String) -> CoFIDFood? {
        foods.first { $0.name == name }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
