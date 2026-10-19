import Foundation

/// Result of reading a nutrition panel. Values are whatever the label printed;
/// the user always reviews them before anything is saved.
public struct ParsedLabel: Equatable, Sendable {
    public var per100: Nutrients?
    public var perServing: Nutrients?
    public var servingGrams: Double?
    public var isLiquid: Bool
    public var warnings: [String]

    public init(
        per100: Nutrients? = nil,
        perServing: Nutrients? = nil,
        servingGrams: Double? = nil,
        isLiquid: Bool = false,
        warnings: [String] = []
    ) {
        self.per100 = per100
        self.perServing = perServing
        self.servingGrams = servingGrams
        self.isLiquid = isLiquid
        self.warnings = warnings
    }

    /// Values per 100 g (or ml), derived from the per serving column when the
    /// label only has that (typical for US labels).
    public var resolvedPer100: Nutrients? {
        if let per100 { return per100 }
        if let perServing, let servingGrams, servingGrams > 0 {
            return perServing.scaled(by: 100 / servingGrams)
        }
        return nil
    }
}

/// Turns OCR'd rows of a nutrition panel into numbers.
///
/// Handles the two common layouts:
/// - UK/EU: columns "per 100g" and "per serving", energy as "kJ / kcal", decimal commas.
/// - US: a single per serving column, "Calories 230", "Serving size 2/3 cup (55g)", % daily values.
///
/// Input is one string per visual row, left to right (see `TextRowGrouper`).
public enum NutritionLabelParser {

    public static func parse(lines rawLines: [String]) -> ParsedLabel {
        let lines = rawLines.map(normalize).filter { !$0.isEmpty }
        var result = ParsedLabel()

        let headerIndex = lines.firstIndex { $0.contains(per100Pattern) }
        let mentions100 = headerIndex != nil
        result.isLiquid = lines.contains { $0.contains(#/100\s?ml/#) }
        result.servingGrams = servingGrams(in: lines, headerIndex: headerIndex)
        let per100First = per100ComesFirst(in: lines)

        var energy: [Double]?
        var kjEnergy: [Double]?
        var fat: [Double]?
        var carbs: [Double]?
        var protein: [Double]?
        var saturates: [Double]?
        var sugars: [Double]?
        var fibre: [Double]?
        var salt: [Double]?
        var sodium: [Double]?

        for line in lines {
            let label = line.drop { !$0.isLetter }
            if isEnergyLine(line) {
                if let kcal = kcalValues(in: line), !kcal.isEmpty {
                    if energy == nil { energy = kcal }
                } else if line.contains("kj"), kjEnergy == nil {
                    let kj = kjValues(in: line)
                    if !kj.isEmpty { kjEnergy = kj }
                }
            } else if fat == nil, isFatLine(label) {
                fat = gramValues(in: line)
            } else if carbs == nil, isCarbLine(label) {
                carbs = gramValues(in: line)
            } else if protein == nil, label.hasPrefix("protein") {
                protein = gramValues(in: line)
            } else if saturates == nil, label.contains("saturate"), !label.contains("unsat") {
                saturates = gramValues(in: line)
            } else if sugars == nil, label.contains("sugar"), !label.contains("added"), !label.contains("alcohol") {
                sugars = gramValues(in: line)
            } else if fibre == nil, label.contains("fibre") || label.contains("fiber") {
                fibre = gramValues(in: line)
            } else if salt == nil, label.hasPrefix("salt") {
                salt = gramValues(in: line)
            } else if sodium == nil, label.hasPrefix("sodium") {
                sodium = sodiumGrams(in: line)
            }
        }

        if energy == nil, let kjEnergy {
            energy = kjEnergy.map { ($0 / 4.184).rounded() }
        }

        func column(_ i: Int) -> Nutrients? {
            guard let energy, energy.indices.contains(i) else { return nil }
            return Nutrients(
                kcal: energy[i],
                protein: protein?[safe: i] ?? 0,
                carbs: carbs?[safe: i] ?? 0,
                fat: fat?[safe: i] ?? 0,
                fibre: fibre?[safe: i],
                sugars: sugars?[safe: i],
                saturatedFat: saturates?[safe: i],
                salt: salt?[safe: i] ?? sodium?[safe: i].map(Nutrients.salt(fromSodiumGrams:))
            )
        }

        if mentions100 {
            let hasTwoColumns = (energy?.count ?? 0) >= 2
            if per100First || !hasTwoColumns {
                result.per100 = column(0)
                result.perServing = column(1)
            } else {
                result.perServing = column(0)
                result.per100 = column(1)
            }
        } else {
            result.perServing = column(0)
        }

        result.warnings = warnings(
            for: result,
            missing: [
                energy == nil ? "calories" : nil,
                protein == nil ? "protein" : nil,
                carbs == nil ? "carbs" : nil,
                fat == nil ? "fat" : nil
            ].compactMap { $0 }
        )
        return result
    }

    // MARK: - Line classification

    private static var per100Pattern: Regex<(Substring, Substring)> { #/100\s?(g|ml)\b/# }

    private static func isEnergyLine(_ line: String) -> Bool {
        let excluded = ["from fat", "diet", "daily value", "a day", "per day"]
        if excluded.contains(where: { line.contains($0) }) { return false }
        return line.contains("energy") || line.contains("kcal") || line.hasPrefix("calories")
            || line.contains(" calories")
    }

    private static func isFatLine(_ label: Substring) -> Bool {
        guard label.hasPrefix("fat") || label.hasPrefix("total fat") else { return false }
        let excluded = ["saturate", "of which", "trans", "mono", "poly", "fatty"]
        return !excluded.contains { label.contains($0) }
    }

    private static func isCarbLine(_ label: Substring) -> Bool {
        let prefixes = ["carbohydrate", "total carbohydrate", "carbs", "total carb", "carb"]
        guard prefixes.contains(where: { label.hasPrefix($0) }) else { return false }
        return !label.contains("of which")
    }

    // MARK: - Header

    private static func per100ComesFirst(in lines: [String]) -> Bool {
        for line in lines {
            guard let hundred = line.firstMatch(of: per100Pattern) else { continue }
            let servingWords = ["serving", "portion", "pack", "bar", "biscuit", "slice"]
            let servingIndex = servingWords
                .compactMap { line.range(of: $0)?.lowerBound }
                .min()
            // A second "per XXg" amount on the header row also counts as the serving column.
            let otherAmount = line.matches(of: #/per\s?(\d+(?:\.\d+)?)\s?(g|ml)/#)
                .first { Double($0.1) != 100 }?.range.lowerBound
            if let other = [servingIndex, otherAmount].compactMap({ $0 }).min() {
                return hundred.range.lowerBound < other
            }
            return true
        }
        return true
    }

    private static func servingGrams(in lines: [String], headerIndex: Int?) -> Double? {
        let servingWords = ["serving", "portion"]
        let candidates = lines.enumerated().filter { index, line in
            index == headerIndex || servingWords.contains { line.contains($0) }
        }
        for (_, line) in candidates {
            for match in line.matches(of: #/(per\s?)?(\d+(?:\.\d+)?)\s?(g|ml)\b/#) {
                guard let value = Double(match.2) else { continue }
                if match.1 != nil && value == 100 { continue }
                if value > 0 && value < 2000 { return value }
            }
        }
        return nil
    }

    // MARK: - Number extraction

    /// kcal values on an energy row. Returns nil when the row has no kcal at all.
    private static func kcalValues(in line: String) -> [Double]? {
        let explicit = line.matches(of: #/(\d+(?:\.\d+)?)\s?kcal/#).compactMap { Double($0.1) }
        if !explicit.isEmpty { return explicit }

        // "energy kj/kcal 1046/250 314/75"
        if let kj = line.range(of: "kj"), let kcal = line.range(of: "kcal") {
            let pairs = line.matches(of: #/(\d+(?:\.\d+)?)\s?/\s?(\d+(?:\.\d+)?)/#)
            if !pairs.isEmpty {
                let kjFirst = kj.lowerBound < kcal.lowerBound
                return pairs.compactMap { Double(kjFirst ? $0.2 : $0.1) }
            }
        }

        if line.contains("kcal") || line.contains("calories") {
            let numbers = plainNumbers(in: line)
            return line.contains("kj") ? nil : numbers
        }
        return nil
    }

    /// "energy 1046kj 314kj" or "energy (kj) 1046 314".
    private static func kjValues(in line: String) -> [Double] {
        let explicit = line.matches(of: #/(\d+(?:\.\d+)?)\s?kj/#).compactMap { Double($0.1) }
        return explicit.isEmpty ? plainNumbers(in: line) : explicit
    }

    /// Numbers not followed by %, mg or another unit that would make them something else.
    private static func plainNumbers(in line: String) -> [Double] {
        line.matches(of: #/(\d+(?:\.\d+)?)\s?(%|mg|mcg|µg|kj|kcal)?/#)
            .filter { $0.2 == nil }
            .compactMap { Double($0.1) }
    }

    /// US labels give sodium in mg ("Sodium 160mg 7%"), some EU labels in g.
    private static func sodiumGrams(in line: String) -> [Double] {
        line.matches(of: #/(\d+(?:\.\d+)?)\s?(mg|g)\b/#).compactMap { match in
            Double(match.1).map { match.2 == "mg" ? $0 / 1000 : $0 }
        }
    }

    private static func gramValues(in line: String) -> [Double] {
        line.matches(of: #/(\d+(?:\.\d+)?)\s?(%|mg|mcg|µg|g)?/#)
            .filter { $0.2 == nil || $0.2 == "g" }
            .compactMap { Double($0.1) }
    }

    // MARK: - Normalisation

    static func normalize(_ raw: String) -> String {
        var line = raw.lowercased()
        // Common OCR slips on labels.
        line = line.replacingOccurrences(of: "kcai", with: "kcal")
        line = line.replacingOccurrences(of: "kca1", with: "kcal")
        line = line.replacingOccurrences(of: "<", with: "")
        line = line.replacingOccurrences(of: "trace", with: "0")
        // Decimal comma ("3,5 g") to dot. Thousands separators are rare on panels.
        line = line.replacing(#/(\d),(\d)/#) { "\($0.1).\($0.2)" }
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Validation

    private static func warnings(for label: ParsedLabel, missing: [String]) -> [String] {
        var warnings: [String] = []
        if !missing.isEmpty {
            warnings.append("Couldn't read \(missing.joined(separator: ", ")). Fill in what's missing.")
        }
        if label.per100 == nil, label.perServing != nil, label.servingGrams == nil {
            warnings.append("Couldn't find the serving size in grams. Add it if you know it, otherwise the values are saved per portion.")
        }
        if let per100 = label.resolvedPer100 {
            if per100.kcal > 900 {
                warnings.append("Calories per 100 g look too high. Check the values.")
            }
            let fromMacros = per100.kcalFromMacros
            if per100.kcal > 0, fromMacros > 0,
               abs(fromMacros - per100.kcal) > max(25, per100.kcal * 0.25) {
                warnings.append("Calories don't match the macros. Double check the numbers.")
            }
        }
        return warnings
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
