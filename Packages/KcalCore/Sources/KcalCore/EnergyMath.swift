import Foundation

public enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case female, male

    public var label: String { rawValue.capitalized }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, active, veryActive

    public var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    public var label: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Light exercise 1 to 3 days"
        case .moderate: "Exercise 3 to 5 days"
        case .active: "Hard exercise 6 to 7 days"
        case .veryActive: "Physical job plus training"
        }
    }
}

public struct EnergyProfile: Codable, Hashable, Sendable {
    public var sex: BiologicalSex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: ActivityLevel
    /// Desired loss per week. 0 means maintain.
    public var weeklyLossKg: Double

    public init(
        sex: BiologicalSex = .female,
        age: Int = 30,
        heightCm: Double = 170,
        weightKg: Double = 75,
        activity: ActivityLevel = .light,
        weeklyLossKg: Double = 0.5
    ) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.weeklyLossKg = weeklyLossKg
    }
}

public struct DailyTarget: Equatable, Sendable {
    public var bmr: Double
    public var maintenance: Double
    public var kcal: Double
    public var macros: Nutrients
    /// Weekly loss actually planned after safety limits are applied.
    public var plannedWeeklyLossKg: Double
    /// Set when the requested rate was reduced or the calorie floor kicked in.
    public var adjustmentNote: String?
    /// Activity calories counted towards maintenance, when they come from Apple Health.
    /// Nil when maintenance uses the activity level multiplier instead.
    public var activityKcal: Double? = nil
}

public enum EnergyMath {
    /// Approximate energy in 1 kg of body fat.
    public static let kcalPerKg = 7700.0

    /// Mifflin-St Jeor resting metabolic rate.
    public static func bmr(_ p: EnergyProfile) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        return base + (p.sex == .male ? 5 : -161)
    }

    public static func maintenance(_ p: EnergyProfile) -> Double {
        bmr(p) * p.activity.multiplier
    }

    /// Resting energy plus the thermic effect of food (about 10%). Measured active
    /// energy already covers all movement above resting, so it is added on top of this
    /// rather than the 1.2 sedentary multiplier, which would count some movement twice.
    public static let thermicEffectMultiplier = 1.1

    /// Common guidance: no faster than about 1% of body weight per week.
    public static func maxWeeklyLoss(weightKg: Double) -> Double {
        weightKg * 0.01
    }

    /// Minimum intake without medical supervision, by commonly cited guidance.
    public static func calorieFloor(_ sex: BiologicalSex) -> Double {
        sex == .male ? 1500 : 1200
    }

    /// - Parameters:
    ///   - activeEnergyKcal: Measured active energy for the day (e.g. from Apple Health).
    ///     Nil uses the activity level multiplier.
    ///   - activeCredit: Share of measured active energy to count, since watches often overestimate it.
    public static func dailyTarget(
        _ p: EnergyProfile,
        activeEnergyKcal: Double? = nil,
        activeCredit: Double = 0.75
    ) -> DailyTarget {
        let bmr = bmr(p)
        let activityKcal = activeEnergyKcal.map { max(0, $0) * activeCredit }
        let maintenance = activityKcal.map { bmr * thermicEffectMultiplier + $0 } ?? maintenance(p)
        var note: String?

        var rate = max(0, p.weeklyLossKg)
        let maxRate = maxWeeklyLoss(weightKg: p.weightKg)
        if rate > maxRate {
            rate = maxRate
            note = "Capped at \(maxRate.formatted(.number.precision(.fractionLength(1)))) kg a week, about 1% of your weight."
        }

        var kcal = maintenance - rate * kcalPerKg / 7
        let floor = calorieFloor(p.sex)
        if kcal < floor {
            kcal = min(floor, maintenance)
            rate = max(0, (maintenance - kcal) * 7 / kcalPerKg)
            note = "Raised to \(Int(kcal)) kcal, the minimum we recommend without medical supervision."
        }

        kcal = (kcal / 10).rounded() * 10
        return DailyTarget(
            bmr: bmr,
            maintenance: maintenance,
            kcal: kcal,
            macros: macroTargets(kcal: kcal, weightKg: p.weightKg),
            plannedWeeklyLossKg: rate,
            adjustmentNote: note,
            activityKcal: activityKcal
        )
    }

    /// Protein is set high (1.8 g/kg, capped at 35% of energy) because it helps
    /// preserve lean mass in a deficit. Fat 27% of energy, carbs take the rest.
    public static func macroTargets(kcal: Double, weightKg: Double) -> Nutrients {
        let protein = min(1.8 * weightKg, kcal * 0.35 / 4)
        let fat = kcal * 0.27 / 9
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return Nutrients(kcal: kcal, protein: protein.rounded(), carbs: carbs.rounded(), fat: fat.rounded())
    }

    /// Exponentially smoothed weight trend. Daily scale readings swing by a kilo or
    /// more with water, so the trend is what we show as "your weight".
    /// Input must be sorted by date ascending.
    public static func trend(_ weights: [Double], smoothing alpha: Double = 0.1) -> [Double] {
        guard var current = weights.first else { return [] }
        return weights.map { w in
            current += alpha * (w - current)
            return current
        }
    }
}
