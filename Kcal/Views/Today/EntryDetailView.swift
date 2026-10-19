import SwiftUI
import SwiftData
import KcalCore

/// Nutrition breakdown for one logged entry, with amount, meal, favourite and delete.
struct EntryDetailView: View {
    let entry: LogEntry
    /// The day's target, for "% of goal" on each macro.
    let target: DailyTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @State private var grams: Double
    @State private var quickKcal: Double
    @State private var meal: Meal
    @State private var confirmingDelete = false

    init(entry: LogEntry, target: DailyTarget) {
        self.entry = entry
        self.target = target
        _grams = State(initialValue: entry.grams)
        _quickKcal = State(initialValue: entry.kcal)
        _meal = State(initialValue: entry.meal)
    }

    private var unit: String { entry.food?.unit ?? "g" }
    private var isLiquid: Bool { entry.food?.isLiquid ?? false }

    /// What the entry will be after the edits on screen, without changing it yet.
    private var portion: Nutrients {
        if entry.isQuickAdd { return Nutrients(kcal: quickKcal) }
        if let per100 = entry.per100, grams > 0 { return per100.forPortion(grams: grams) }
        return entry.nutrients
    }

    private var hasChanges: Bool {
        meal != entry.meal || (entry.isQuickAdd ? quickKcal != entry.kcal : grams != entry.grams)
    }

    private var source: String {
        if entry.isQuickAdd { return FoodSource.quickAdd.label }
        if entry.recipe != nil || !entry.ingredientNotes.isEmpty { return "Homemade" }
        return entry.food?.source.label ?? "Food since deleted"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text(portion.kcal, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: portion.kcal))
                        Text(entry.isQuickAdd || !entry.ingredientNotes.isEmpty ? "kcal" : "kcal in \(grams.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .animation(.smooth, value: portion)
                }
                .listRowBackground(Theme.surface)

                if !entry.ingredientNotes.isEmpty {
                    Section("Ingredients") {
                        ForEach(entry.ingredientNotes, id: \.self) { note in
                            Text(note).font(.subheadline)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                if !entry.isQuickAdd {
                    Section("Macros") {
                        macroRow("Protein", portion.protein, goal: target.macros.protein, tint: Theme.protein)
                        macroRow("Carbs", portion.carbs, goal: target.macros.carbs, tint: Theme.carbs)
                        macroRow("Fat", portion.fat, goal: target.macros.fat, tint: Theme.fat)
                    }
                    .listRowBackground(Theme.surface)

                    Section("Where the calories come from") {
                        CalorieSplit(nutrients: portion)
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        detailRow("Fibre", portion.fibre, per100: entry.per100?.fibre, light: nil)
                        detailRow("Sugars", portion.sugars, per100: entry.per100?.sugars, light: .sugars)
                        detailRow("Saturates", portion.saturatedFat, per100: entry.per100?.saturatedFat, light: .saturatedFat)
                        detailRow("Salt", portion.salt, per100: entry.per100?.salt, light: .salt)
                    } header: {
                        Text("Detail")
                    } footer: {
                        Text("Colours follow UK front-of-pack guidance per 100 \(unit): green low, amber medium, red high.")
                    }
                    .listRowBackground(Theme.surface)

                    if let per100 = entry.per100 {
                        Section("Per 100 \(unit)") {
                            value("Calories", per100.kcal, unit: "kcal")
                            value("Protein", per100.protein, unit: "g")
                            value("Carbs", per100.carbs, unit: "g")
                            value("Fat", per100.fat, unit: "g")
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                Section("Entry") {
                    if entry.isQuickAdd {
                        editableNumber("Calories", $quickKcal, unit: "kcal")
                    } else {
                        editableNumber("Amount", $grams, unit: unit)
                    }
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    LabeledContent("Source", value: source)
                    if let food = entry.food {
                        Toggle(isOn: Bindable(food).isFavorite) {
                            Label("Favourite", systemImage: "star")
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button("Delete entry", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                    .tint(.red)
                }
                .listRowBackground(Theme.surface)
            }
            .themedList()
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasChanges {
                    Button(action: save) {
                        Text("Save changes")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .foregroundStyle(Theme.onTint)
                    .disabled(entry.isQuickAdd ? quickKcal <= 0 : grams <= 0)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: hasChanges)
            .confirmationDialog("Delete \(entry.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        if entry.isQuickAdd {
            entry.kcal = quickKcal
        } else {
            entry.setPortion(grams: grams)
        }
        entry.meal = meal
        Task { await health.update(entry) }
        dismiss()
    }

    private func delete() {
        let syncIDs = [entry.healthSyncID].compactMap { $0 }
        context.delete(entry)
        Task { await health.deleteFood(syncIDs: syncIDs) }
        dismiss()
    }

    // MARK: Rows

    private func macroRow(_ name: String, _ grams: Double, goal: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                Spacer()
                Text("\(grams.formatted(.number.precision(.fractionLength(0...1)))) g")
                    .monospacedDigit()
                if goal > 0 {
                    Text("\(Int((grams / goal * 100).rounded()))% of goal")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                        .frame(minWidth: 76, alignment: .trailing)
                }
            }
            ProgressView(value: min(grams, max(goal, 1)), total: max(goal, 1))
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailRow(_ name: String, _ amount: Double?, per100: Double?, light: TrafficLight.Nutrient?) -> some View {
        HStack {
            // Rows without a rating keep the dot's space so the names line up.
            let rating = light.flatMap { light in per100.map { TrafficLight.rating(light, per100: $0, isLiquid: isLiquid) } }
            Circle()
                .fill(rating?.color ?? .clear)
                .frame(width: 10, height: 10)
                .accessibilityLabel(rating?.rawValue ?? "")
                .accessibilityHidden(rating == nil)
            Text(name)
            Spacer()
            if let amount {
                Text("\(amount.formatted(.number.precision(.fractionLength(0...2)))) g")
                    .monospacedDigit()
            } else {
                Text("Not available").foregroundStyle(.tertiary)
            }
        }
    }

    private func value(_ name: String, _ amount: Double, unit: String) -> some View {
        LabeledContent(name) {
            Text("\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                .monospacedDigit()
        }
    }

    private func editableNumber(_ title: String, _ value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(Theme.secondaryText)
        }
    }
}

/// A single bar split by the share of calories from protein, carbs and fat (4/4/9 kcal per g).
struct CalorieSplit: View {
    let nutrients: Nutrients

    private var parts: [(name: String, kcal: Double, tint: Color)] {
        [("Protein", nutrients.protein * 4, Theme.protein), ("Carbs", nutrients.carbs * 4, Theme.carbs), ("Fat", nutrients.fat * 9, Theme.fat)]
    }

    var body: some View {
        let total = parts.reduce(0) { $0 + $1.kcal }
        if total <= 0 {
            Text("No macro information").foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.name) { part in
                            if part.kcal > 0 {
                                Rectangle()
                                    .fill(part.tint)
                                    .frame(width: max(2, (proxy.size.width - 4) * part.kcal / total))
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(.capsule)
                HStack(spacing: 16) {
                    ForEach(parts, id: \.name) { part in
                        HStack(spacing: 6) {
                            Circle().fill(part.tint).frame(width: 8, height: 8)
                            Text("\(part.name) \(Int((part.kcal / total * 100).rounded()))%")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

extension TrafficLight {
    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}
