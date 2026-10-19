import SwiftUI
import KcalCore

/// Calories remaining as a ring, macros as bars underneath.
struct SummaryCard: View {
    let eaten: Nutrients
    let target: DailyTarget

    private var remaining: Double { target.kcal - eaten.kcal }
    private var progress: Double { target.kcal > 0 ? eaten.kcal / target.kcal : 0 }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                CalorieRing(progress: progress)
                    .frame(width: 190, height: 190)
                VStack(spacing: 2) {
                    Text(abs(remaining), format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: remaining))
                    Text(remaining >= 0 ? "kcal left" : "kcal over")
                        .font(.subheadline)
                        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
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
                stat("Goal", target.kcal)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 32))
        .padding(.horizontal)
        .animation(.smooth, value: eaten)
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CalorieRing: View {
    let progress: Double
    private let lineWidth: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    AngularGradient(colors: [.green, .mint, .green], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
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
