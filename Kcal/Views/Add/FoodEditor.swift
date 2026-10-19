import SwiftUI
import KcalCore

/// Editable food details, from a label scan, a blank form or an existing food.
/// Values are in the chosen basis (per 100 g/ml or per serving). Per-serving values
/// with a serving weight are saved per 100 g; without one, the food is saved per portion.
struct FoodDraft {
    enum Basis: String, CaseIterable { case per100 = "Per 100 g", perServing = "Per serving" }

    var name = ""
    var brand = ""
    var barcode = ""
    var basis = Basis.per100
    var values = Nutrients.zero
    var servingGrams: Double?
    var isLiquid = false
    var warnings: [String] = []

    init(name: String = "", barcode: String? = nil) {
        self.name = name
        self.barcode = barcode ?? ""
    }

    init(parsed: ParsedLabel, barcode: String?) {
        self.barcode = barcode ?? ""
        servingGrams = parsed.servingGrams
        isLiquid = parsed.isLiquid
        warnings = parsed.warnings
        if let per100 = parsed.per100 {
            values = per100
        } else if let perServing = parsed.perServing {
            basis = .perServing
            values = perServing
        }
    }

    init(food: Food) {
        name = food.name
        brand = food.brand ?? ""
        barcode = food.barcode ?? ""
        values = food.per100
        servingGrams = food.servingGrams
        isLiquid = food.isLiquid
        if food.isPerPortion { basis = .perServing }
    }

    var unit: String { isLiquid ? "ml" : "g" }

    private var weight: Double? { servingGrams.flatMap { $0 > 0 ? $0 : nil } }

    /// Per serving with no weight: keep the values per portion, don't invent per 100 g.
    var isPerPortion: Bool { basis == .perServing && weight == nil }

    /// Values as stored: per 100 g/ml, or per portion when `isPerPortion`.
    var stored: Nutrients {
        switch basis {
        case .per100: values
        case .perServing: weight.map { values.scaled(by: 100 / $0) } ?? values
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && values.kcal > 0
    }

    /// A new food candidate, or nil while the form is incomplete.
    func candidate(source: FoodSource, id: String? = nil) -> FoodCandidate? {
        guard isValid else { return nil }
        let brand = brand.trimmingCharacters(in: .whitespaces)
        let barcode = barcode.trimmingCharacters(in: .whitespaces)
        return FoodCandidate(
            id: id ?? "\(source.rawValue):\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand,
            barcode: barcode.isEmpty ? nil : barcode,
            per100: stored,
            servingGrams: weight,
            servingLabel: weight.map { "\($0.formatted()) \(unit)" },
            isLiquid: isLiquid,
            source: source,
            isPerPortion: isPerPortion
        )
    }
}

/// Form for creating or editing a food. Used for label scans, "Create food" and My foods.
struct FoodEditor: View {
    @State var draft: FoodDraft
    var rows: [String] = []
    var title = "New food"
    var saveTitle = "Save"
    var footer: String?
    let onSave: (FoodDraft) -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            if !draft.warnings.isEmpty {
                Section {
                    ForEach(draft.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section("Product") {
                TextField("Name (required)", text: $draft.name)
                    .focused($nameFocused)
                TextField("Brand", text: $draft.brand)
                TextField("Barcode", text: $draft.barcode)
                    .keyboardType(.numberPad)
                Toggle("Drink (values per ml)", isOn: $draft.isLiquid)
            }
            .listRowBackground(Theme.surface)

            Section {
                Picker("Values are", selection: $draft.basis) {
                    ForEach(FoodDraft.Basis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                number("Calories", $draft.values.kcal, unit: "kcal")
                number("Protein", $draft.values.protein, unit: "g")
                number("Carbs", $draft.values.carbs, unit: "g")
                number("Fat", $draft.values.fat, unit: "g")
            } header: {
                Text("Nutrition")
            } footer: {
                if let footer { Text(footer) }
            }
            .listRowBackground(Theme.surface)

            Section("More detail (optional)") {
                optional("Fibre", $draft.values.fibre)
                optional("Sugars", $draft.values.sugars)
                optional("Saturates", $draft.values.saturatedFat)
                optional("Salt", $draft.values.salt)
            }
            .listRowBackground(Theme.surface)

            Section {
                HStack {
                    TextField("Weight of one serving", value: $draft.servingGrams, format: .number)
                        .keyboardType(.decimalPad)
                    Text(draft.unit).foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Serving size (optional)")
            } footer: {
                if draft.isPerPortion {
                    Text("No weight, so this is saved per portion and logged in portions. Add the weight if you'd like to log it in \(draft.unit).")
                } else if draft.basis == .perServing {
                    Text("Values are worked out per 100 \(draft.unit) from this weight.")
                }
            }
            .listRowBackground(Theme.surface)

            if !rows.isEmpty {
                Section {
                    DisclosureGroup("What the camera read") {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Text(row).font(.caption.monospaced())
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .themedList()
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameFocused = draft.name.isEmpty }
        .safeAreaInset(edge: .bottom) {
            Button { onSave(draft) } label: {
                Text(saveTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(Theme.onTint)
            .disabled(!draft.isValid)
            .padding()
        }
    }

    private func number(_ title: String, _ value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func optional(_ title: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text("g")
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 36, alignment: .leading)
        }
    }
}
