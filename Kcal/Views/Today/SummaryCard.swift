import SwiftUI
import KcalCore

/// Calories remaining as a ring, macros as bars underneath.
/// The ring is the day's goal plus anything earned by activity, which shows in blush after a small gap.
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
                        .foregroundStyle(remaining >= 0 ? Theme.secondaryText : Theme.over)
                    if target.earnedKcal >= 1 {
                        Text("incl. +\(Int(target.earnedKcal.rounded())) from activity")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.earnedText)
                            .transition(.opacity)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 16) {
                MacroBar(name: "Protein", value: eaten.protein, goal: target.macros.protein, tint: Theme.protein)
                MacroBar(name: "Carbs", value: eaten.carbs, goal: target.macros.carbs, tint: Theme.carbs)
                MacroBar(name: "Fat", value: eaten.fat, goal: target.macros.fat, tint: Theme.fat)
            }

            HStack {
                stat("Eaten", eaten.kcal)
                Divider().frame(height: 28)
                stat("Goal", target.baseKcal)
                if showsActivity {
                    Divider().frame(height: 28)
                    stat("Activity", target.earnedKcal, sign: "+", tint: Theme.earnedText)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: .rect(cornerRadius: 32))
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
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One full turn is goal plus earned. The goal part is a Cocoa arc on a Sand track; the
/// earned part follows after a small gap in blush (faint until eaten into). Going over
/// adds a thinner terracotta ring outside, so the three states differ in shape as well
/// as colour.
struct CalorieRing: View {
    let eaten: Double
    let base: Double
    let earned: Double
    private let lineWidth: CGFloat = 16
    private let overWidth: CGFloat = 5
    private let overGap: CGFloat = 4

    private var total: Double { max(base + earned, 1) }
    private var baseEnd: Double { min(base / total, 1) }
    /// Space between the goal and earned zones, as a fraction of the circle.
    private var gap: Double { earned > 0 ? 0.02 : 0 }
    private var eatenFraction: Double { eaten / total }

    var body: some View {
        ZStack {
            ZStack {
                arc(0, baseEnd, Theme.ringTrack, cap: .butt)
                if earned > 0 {
                    arc(baseEnd + gap, 1, Theme.earned.opacity(0.3), cap: .butt)
                    if eatenFraction > baseEnd + gap {
                        arc(baseEnd + gap, min(eatenFraction, 1), Theme.earned, cap: .butt)
                    }
                }
                arc(0, min(eatenFraction, baseEnd), Theme.ringGoal)
            }
            .padding(overWidth + overGap)

            if eatenFraction > 1 {
                Circle()
                    .trim(from: 0, to: min(eatenFraction - 1, 1))
                    .stroke(Theme.over, style: StrokeStyle(lineWidth: overWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(overWidth / 2)
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
                .foregroundStyle(Theme.secondaryText)
            ProgressView(value: min(value, goal), total: max(goal, 1))
                .tint(tint)
            Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
