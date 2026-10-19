import SwiftUI
import SwiftData
import KcalCore

/// Choose how much and which meal, then log. Used by every add flow.
struct PortionView: View {
    let candidate: FoodCandidate
    /// The saved food, when there is one. Remote results are only saved once logged.
    let existing: Food?
    let day: Date
    let onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @State private var amount: Double
    @State private var unit: PortionUnit
    @State private var meal = Meal.suggested()

    enum PortionUnit: Hashable { case grams, servings }

    init(candidate: FoodCandidate, existing: Food? = nil, day: Date, onLogged: @escaping () -> Void) {
        self.candidate = candidate
        self.existing = existing
        self.day = day
        self.onLogged = onLogged
        let hasServing = (candidate.servingGrams ?? 0) > 0
        _unit = State(initialValue: hasServing ? .servings : .grams)
        _amount = State(initialValue: hasServing ? 1 : 100)
    }

    private var unitLabel: String { candidate.isLiquid ? "ml" : "g" }

    private var grams: Double {
        switch unit {
        case .grams: amount
        case .servings: amount * (candidate.servingGrams ?? 100)
        }
    }

    private var portion: Nutrients { candidate.per100.forPortion(grams: grams) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Text(portion.kcal, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: portion.kcal))
                    Text("kcal")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        macro("Protein", portion.protein)
                        macro("Carbs", portion.carbs)
                        macro("Fat", portion.fat)
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .animation(.smooth, value: grams)
            }

            Section("Amount") {
                HStack {
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    if candidate.servingGrams != nil {
                        Picker("Unit", selection: $unit) {
                            Text(unitLabel).tag(PortionUnit.grams)
                            Text("servings").tag(PortionUnit.servings)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .onChange(of: unit) { _, new in
                            amount = new == .servings ? 1 : (candidate.servingGrams ?? 100).rounded()
                        }
                    } else {
                        Text(unitLabel).foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(quickAmounts, id: \.self) { value in
                            Button(quickLabel(value)) { amount = value }
                                .buttonStyle(.glass)
                        }
                    }
                }
                if let label = candidate.servingLabel, unit == .servings {
                    Text("1 serving = \(label)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle(candidate.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: log) {
                Text("Log \(Int(portion.kcal.rounded())) kcal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(grams <= 0)
            .padding()
        }
    }

    private var quickAmounts: [Double] {
        unit == .servings ? [0.5, 1, 1.5, 2] : [25, 50, 100, 150, 200]
    }

    private func quickLabel(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return unit == .servings ? "\(number)×" : "\(number) \(unitLabel)"
    }

    private func macro(_ name: String, _ grams: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(grams, format: .number.precision(.fractionLength(0...1))) g")
                .font(.headline.monospacedDigit())
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func log() {
        let food = existing ?? context.food(for: candidate)
        context.log(food, grams: grams, meal: meal, on: day)
        onLogged()
    }
}
