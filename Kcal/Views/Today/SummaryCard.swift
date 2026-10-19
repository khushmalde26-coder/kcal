import SwiftUI
import KcalCore

extension Color {
    /// Calories earned by activity beyond the usual level.
    static let earned = Color(red: 1.0, green: 0.62, blue: 0.0)
}

/// Calories remaining as a ring, macros as bars underneath.
/// The ring is the day's goal plus anything earned by activity, which shows in amber.
struct SummaryCard: View {
    let eaten: Nutrients
    let target: DailyTarget
    /// Apple Health is on, so the Activity stat is shown even before anything is earned.
    var showsActivity = false

    private var remaining: Double { target.totalKcal - eaten.kcal }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                CalorieRing(eaten: eaten.kcal, base: target.baseKcal, earned: target.earnedKcal)
                    .frame(width: 190, height: 190)
                VStack(spacing: 2) {
                    Text(abs(remaining), format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: remaining))
                    Text(remaining >= 0 ? "kcal left" : "kcal over")
                        .font(.subheadline)
                        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
                    if target.earnedKcal >= 1 {
                        Text("incl. +\(Int(target.earnedKcal.rounded())) from activity")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.earned)
                            .transition(.opacity)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 16) {
                MacroBar(name: "Protein", value: eaten.protein, goal: target.macros.protein, tint: .blue)
                MacroBar(name: "Carbs", value: eaten.carbs, goal: target.macros.carbs, tint: .teal)
                MacroBar(name: "Fat", value: eaten.fat, goal: target.macros.fat, tint: .pink)
            }

            HStack {
                stat("Eaten", eaten.kcal)
                Divider().frame(height: 28)
                stat("Goal", target.baseKcal)
                if showsActivity {
                    Divider().frame(height: 28)
                    stat("Activity", target.earnedKcal, sign: "+", tint: .earned)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 32))
        .padding(.horizontal)
        .animation(.smooth, value: eaten)
        .animation(.smooth, value: target)
    }

    private func stat(_ title: String, _ value: Double, sign: String = "", tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(sign + value.formatted(.number.precision(.fractionLength(0))))
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: value))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One full turn is goal plus earned. The track is grey for the goal and faint amber
/// for the earned room at the end; the fill is green through the goal, amber through
/// the earned part, and red for anything beyond both.
struct CalorieRing: View {
    let eaten: Double
    let base: Double
    let earned: Double
    private let lineWidth: CGFloat = 18

    private var total: Double { max(base + earned, 1) }
    private var baseEnd: Double { min(base / total, 1) }
    private var eatenFraction: Double { eaten / total }

    var body: some View {
        ZStack {
            arc(0, baseEnd, .quaternary, cap: .butt)
            if earned > 0 {
                arc(baseEnd, 1, Color.earned.opacity(0.25), cap: .butt)
            }
            if eatenFraction > baseEnd {
                arc(baseEnd, min(eatenFraction, 1), Color.earned)
            }
            arc(0, min(eatenFraction, baseEnd), AngularGradient(colors: [.green, .mint, .green], center: .center))
            if eatenFraction > 1 {
                arc(0, min(eatenFraction - 1, 1), Color.red)
            }
        }
    }

    private func arc(_ from: Double, _ to: Double, _ style: some ShapeStyle, cap: CGLineCap = .round) -> some View {
        Circle()
            .trim(from: from, to: max(from, to))
            .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: cap))
            .rotationEffect(.degrees(-90))
            .opacity(to > from ? 1 : 0)
    }
}

struct MacroBar: View {
    let name: String
    let value: Double
    let goal: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: min(value, goal), total: max(goal, 1))
                .tint(tint)
            Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
