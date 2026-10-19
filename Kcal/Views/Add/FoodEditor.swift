import SwiftUI
import KcalCore

/// Editable food details, from a label scan, a blank form or an existing food.
/// Values are in the chosen basis (per 100 g/ml or per serving).
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
    }

    var unit: String { isLiquid ? "ml" : "g" }

    var per100: Nutrients? {
        switch basis {
        case .per100: values
        case .perServing:
            servingGrams.flatMap { $0 > 0 ? values.scaled(by: 100 / $0) : nil }
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && per100 != nil && values.kcal > 0
    }

    /// A new food candidate, or nil while the form is incomplete.
    func candidate(source: FoodSource, id: String? = nil) -> FoodCandidate? {
        guard isValid, let per100 else { return nil }
        let brand = brand.trimmingCharacters(in: .whitespaces)
        let barcode = barcode.trimmingCharacters(in: .whitespaces)
        return FoodCandidate(
            id: id ?? "\(source.rawValue):\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand,
            barcode: barcode.isEmpty ? nil : barcode,
            per100: per100,
            servingGrams: servingGrams.flatMap { $0 > 0 ? $0 : nil },
            servingLabel: servingGrams.flatMap { $0 > 0 ? "\($0.formatted()) \(unit)" : nil },
            isLiquid: isLiquid,
            source: source
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
            }

            Section("Product") {
                TextField("Name (required)", text: $draft.name)
                    .focused($nameFocused)
                TextField("Brand", text: $draft.brand)
                TextField("Barcode", text: $draft.barcode)
                    .keyboardType(.numberPad)
                Toggle("Drink (values per ml)", isOn: $draft.isLiquid)
            }

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

            Section("More detail (optional)") {
                optional("Fibre", $draft.values.fibre)
                optional("Sugars", $draft.values.sugars)
                optional("Saturates", $draft.values.saturatedFat)
                optional("Salt", $draft.values.salt)
            }

            Section {
                HStack {
                    TextField("Optional", value: $draft.servingGrams, format: .number)
                        .keyboardType(.decimalPad)
                    Text(draft.unit).foregroundStyle(.secondary)
                }
            } header: {
                Text("Serving size")
            } footer: {
                if draft.basis == .perServing && (draft.servingGrams ?? 0) <= 0 {
                    Text("Needed to work out values per 100 \(draft.unit).")
                }
            }

            if !rows.isEmpty {
                Section {
                    DisclosureGroup("What the camera read") {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Text(row).font(.caption.monospaced())
                        }
                    }
                }
            }
        }
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}
