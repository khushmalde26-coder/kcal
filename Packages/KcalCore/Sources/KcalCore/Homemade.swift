import Foundation

/// A portion choice offered as a chip, e.g. "splash" = 30 ml.
public struct PortionChoice: Hashable, Sendable {
    public var label: String
    public var grams: Double

    public init(_ label: String, _ grams: Double) {
        self.label = label
        self.grams = grams
    }
}

/// Everyday products people re-buy. Each has a default product the user picks
/// (their milk, their bread); until they do, a generic UK food stands in.
public enum StapleSlot: String, CaseIterable, Codable, Sendable, Identifiable {
    case milk, bread, eggs, butter, oil, cheese, sugar, oats, cereal, rice, pasta, yoghurt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .milk: "Milk"
        case .bread: "Bread"
        case .eggs: "Eggs"
        case .butter: "Butter or spread"
        case .oil: "Cooking oil"
        case .cheese: "Cheese"
        case .sugar: "Sugar"
        case .oats: "Oats"
        case .cereal: "Cereal"
        case .rice: "Rice"
        case .pasta: "Pasta"
        case .yoghurt: "Yoghurt"
        }
    }

    /// Lowercase noun for prompts like "Which milk do you use?".
    public var noun: String {
        switch self {
        case .butter: "butter or spread"
        case .oil: "cooking oil"
        default: title.lowercased()
        }
    }

    public var symbol: String {
        switch self {
        case .milk: "waterbottle"
        case .bread: "rectangle.stack"
        case .eggs: "oval.portrait"
        case .butter: "square.fill"
        case .oil: "drop"
        case .cheese: "triangle"
        case .sugar: "cube"
        case .oats: "leaf"
        case .cereal: "takeoutbag.and.cup.and.straw"
        case .rice: "circle.grid.3x3"
        case .pasta: "scribble"
        case .yoghurt: "cup.and.saucer"
        }
    }

    public var isLiquid: Bool { self == .milk || self == .oil }
    public var unit: String { isLiquid ? "ml" : "g" }

    /// CoFID food used until the user picks their own product.
    public var fallbackCoFIDName: String {
        switch self {
        case .milk: "Milk, semi-skimmed, pasteurised, average"
        case .bread: "Bread, white, sliced"
        case .eggs: "Eggs, chicken, whole, raw"
        case .butter: "Butter, salted"
        case .oil: "Oil, vegetable, average"
        case .cheese: "Cheese, Cheddar, English"
        case .sugar: "Sugar, white"
        case .oats: "Porridge oats, unfortified"
        case .cereal: "Breakfast cereal, cornflakes, fortified"
        case .rice: "Rice, white, long grain, raw"
        case .pasta: "Pasta, white, dried, raw"
        case .yoghurt: "Yogurt, whole milk, plain"
        }
    }

    /// Quick amounts. Bread uses the product's own slice size when it has one.
    public func portions(servingGrams: Double? = nil) -> [PortionChoice] {
        switch self {
        case .milk: return [.init("Splash", 30), .init("Dash", 50), .init("Small glass", 150), .init("Latte", 200)]
        case .bread:
            let slice = servingGrams.flatMap { $0 > 0 && $0 < 100 ? $0 : nil } ?? 36
            return [.init("1 slice", slice), .init("2 slices", slice * 2)]
        case .eggs: return [.init("1 egg", 50), .init("2 eggs", 100), .init("3 eggs", 150)]
        case .butter: return [.init("Thin spread", 7), .init("Thick spread", 12), .init("Knob", 10)]
        case .oil: return [.init("1 tsp", 5), .init("1 tbsp", 14)]
        case .cheese: return [.init("Sprinkle", 15), .init("Matchbox", 30), .init("Grated handful", 40)]
        case .sugar: return [.init("1 tsp", 4), .init("2 tsp", 8)]
        case .oats: return [.init("Small bowl", 30), .init("Bowl", 40), .init("Big bowl", 60)]
        case .cereal: return [.init("Small bowl", 30), .init("Bowl", 40), .init("Big bowl", 60)]
        case .rice: return [.init("Portion (dry)", 75), .init("Large (dry)", 100)]
        case .pasta: return [.init("Portion (dry)", 75), .init("Large (dry)", 100)]
        case .yoghurt: return [.init("Pot", 125), .init("Big spoonful", 50), .init("Bowl", 150)]
        }
    }

    /// The slot a scanned product most likely fills, from its name, e.g. "Oat drink" → milk.
    public static func match(productName: String) -> StapleSlot? {
        let name = productName.lowercased()
        let rules: [(StapleSlot, [String])] = [
            (.milk, ["milk", "oat drink", "soya drink", "almond drink", "oat m"]),
            (.butter, ["butter", "spread", "margarine"]),
            (.yoghurt, ["yoghurt", "yogurt"]),
            (.cheese, ["cheddar", "cheese"]),
            (.oil, [" oil", "oil "]),
            (.bread, ["bread", "loaf", "bloomer", "sourdough", "toastie"]),
            (.eggs, ["eggs"]),
            (.oats, ["oats", "porridge"]),
            (.cereal, ["cornflakes", "bran flakes", "cereal", "granola", "muesli", "weetabix"]),
            (.sugar, ["sugar"]),
            (.rice, ["rice"]),
            (.pasta, ["pasta", "spaghetti", "penne", "fusilli"]),
        ]
        // Order matters: "milk chocolate" isn't milk, "buttermilk" is close enough to milk.
        if name.contains("chocolate") || name.contains("biscuit") { return nil }
        return rules.first { _, words in words.contains { name.contains($0) } }?.0
    }
}

/// A homemade item to set up from: questions about the user's staples plus fixed bases.
public struct HomemadeTemplate: Identifiable, Sendable {
    public enum Part: Sendable {
        case staple(StapleSlot)
        /// A generic food from CoFID, by exact name.
        case generic(String)
    }

    public struct Item: Sendable {
        public var part: Part
        /// "Which milk do you use?" style prompt.
        public var question: String
        public var grams: Double
        public var portions: [PortionChoice]
        /// Optional extras (sugar) start at zero and are left out when zero.
        public var isOptional: Bool
        /// Drinks measured in ml (CoFID lists coffee and tea per 100 g).
        public var isLiquid: Bool

        public init(_ part: Part, question: String, grams: Double, portions: [PortionChoice] = [],
                    isOptional: Bool = false, isLiquid: Bool = false) {
            self.part = part
            self.question = question
            self.grams = grams
            self.portions = portions
            self.isOptional = isOptional
            self.isLiquid = isLiquid
        }
    }

    public var id: String
    public var name: String
    public var savedName: String
    public var symbol: String
    public var items: [Item]

    public static let all: [HomemadeTemplate] = [
        HomemadeTemplate(id: "coffee", name: "Coffee with milk", savedName: "My coffee", symbol: "cup.and.saucer.fill", items: [
            Item(.generic("Coffee, infusion, average"), question: "How big a coffee?", grams: 200,
                 portions: [.init("Espresso", 30), .init("Cup", 200), .init("Mug", 300)], isLiquid: true),
            Item(.staple(.milk), question: "Which milk do you use?", grams: 30),
            Item(.staple(.sugar), question: "Any sugar?", grams: 0, isOptional: true),
        ]),
        HomemadeTemplate(id: "tea", name: "Tea with milk", savedName: "My tea", symbol: "mug.fill", items: [
            Item(.generic("Tea, black, infusion, average"), question: "How big a tea?", grams: 250,
                 portions: [.init("Cup", 200), .init("Mug", 300)], isLiquid: true),
            Item(.staple(.milk), question: "Which milk do you use?", grams: 30),
            Item(.staple(.sugar), question: "Any sugar?", grams: 0, isOptional: true),
        ]),
        HomemadeTemplate(id: "toast", name: "Toast with butter", savedName: "My toast", symbol: "square.stack.fill", items: [
            Item(.staple(.bread), question: "Which bread do you use?", grams: 72),
            Item(.staple(.butter), question: "What do you spread on it?", grams: 14,
                 portions: [.init("Thin, 1 slice", 7), .init("Thin, 2 slices", 14), .init("Thick, 2 slices", 24)]),
        ]),
        HomemadeTemplate(id: "scrambled", name: "Scrambled eggs", savedName: "My scrambled eggs", symbol: "frying.pan.fill", items: [
            Item(.staple(.eggs), question: "How many eggs?", grams: 100),
            Item(.staple(.milk), question: "Any milk in them?", grams: 30, isOptional: true),
            Item(.staple(.butter), question: "Butter in the pan?", grams: 7, isOptional: true),
        ]),
        HomemadeTemplate(id: "fried-egg", name: "Fried egg", savedName: "My fried egg", symbol: "frying.pan", items: [
            Item(.staple(.eggs), question: "How many eggs?", grams: 50),
            Item(.staple(.oil), question: "Which oil do you fry in?", grams: 5),
        ]),
        HomemadeTemplate(id: "porridge", name: "Porridge with milk", savedName: "My porridge", symbol: "takeoutbag.and.cup.and.straw.fill", items: [
            Item(.staple(.oats), question: "Which oats do you use?", grams: 40),
            Item(.staple(.milk), question: "Which milk, and how much?", grams: 200,
                 portions: [.init("Half and half with water", 100), .init("Mug", 200), .init("Big mug", 300)]),
            Item(.staple(.sugar), question: "Any sugar?", grams: 0, isOptional: true),
        ]),
        HomemadeTemplate(id: "cereal", name: "Cereal with milk", savedName: "My cereal", symbol: "fork.knife", items: [
            Item(.staple(.cereal), question: "Which cereal do you eat?", grams: 40),
            Item(.staple(.milk), question: "Which milk, and how much?", grams: 125,
                 portions: [.init("Splash", 75), .init("Normal", 125), .init("Lots", 200)]),
        ]),
    ]
}

/// Totals for homemade items: ingredient values are per 100 g/ml.
public enum RecipeMath {
    public static func total(_ ingredients: [(per100: Nutrients, grams: Double)]) -> Nutrients {
        ingredients.reduce(.zero) { $0 + $1.per100.forPortion(grams: $1.grams) }
    }

    public static func perServing(_ total: Nutrients, servings: Double) -> Nutrients {
        servings > 0 ? total.scaled(by: 1 / servings) : total
    }

    public static func per100(_ total: Nutrients, totalGrams: Double) -> Nutrients? {
        totalGrams > 0 ? total.scaled(by: 100 / totalGrams) : nil
    }
}
