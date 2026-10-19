import Foundation

/// UK front-of-pack colour coding (FSA / Department of Health 2016 guidance), per 100 g
/// or per 100 ml. The per-portion "red" rule for large portions is not applied.
public enum TrafficLight: String, Sendable {
    case low, medium, high

    public enum Nutrient: Sendable {
        case fat, saturatedFat, sugars, salt
    }

    public static func rating(_ nutrient: Nutrient, per100 value: Double, isLiquid: Bool) -> TrafficLight {
        let (low, high): (Double, Double) = switch (nutrient, isLiquid) {
        case (.fat, false): (3, 17.5)
        case (.fat, true): (1.5, 8.75)
        case (.saturatedFat, false): (1.5, 5)
        case (.saturatedFat, true): (0.75, 2.5)
        case (.sugars, false): (5, 22.5)
        case (.sugars, true): (2.5, 11.25)
        case (.salt, false): (0.3, 1.5)
        case (.salt, true): (0.3, 0.75)
        }
        if value <= low { return .low }
        return value > high ? .high : .medium
    }
}
