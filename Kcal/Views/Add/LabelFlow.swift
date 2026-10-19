import SwiftUI
import SwiftData
import KcalCore

/// Photo of a nutrition panel → on-device OCR → user reviews the numbers →
/// product is saved (with its barcode if we came from a failed scan) → portion → logged.
struct LabelFlow: View {
    let day: Date
    let barcode: String?
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @State private var state: LabelState = .capture

    enum LabelState {
        case capture
        case reading
        case review(LabelDraft, rows: [String])
        case portion(Food)
        case failed(String)
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { dismiss() }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .capture:
            VStack(spacing: 0) {
                if barcode != nil {
                    Text("This product isn't in the database yet. Take a photo of its nutrition label to add it.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                CameraPicker(onImage: { image in Task { await read(image) } }, onCancel: { dismiss() })
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Scan label")
            .navigationBarTitleDisplayMode(.inline)
        case .reading:
            ProgressView("Reading label…")
        case .review(let draft, let rows):
            LabelReviewForm(draft: draft, rows: rows) { food in
                state = .portion(food)
            }
        case .portion(let food):
            PortionView(candidate: food.candidate, existing: food, day: day) { dismiss() }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't read the label", systemImage: "text.viewfinder")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { state = .capture }
                    .buttonStyle(.glassProminent)
                Button("Enter it manually") {
                    state = .review(LabelDraft(barcode: barcode), rows: [])
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func read(_ image: UIImage) async {
        state = .reading
        do {
            let rows = try await LabelReader.rows(in: image)
            let parsed = NutritionLabelParser.parse(lines: rows)
            state = .review(LabelDraft(parsed: parsed, barcode: barcode), rows: rows)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Editable values from a scanned label. Values are in the chosen basis.
struct LabelDraft {
    enum Basis: String, CaseIterable { case per100 = "Per 100 g", perServing = "Per serving" }

    var name = ""
    var brand = ""
    var barcode: String?
    var basis = Basis.per100
    var values = Nutrients.zero
    var servingGrams: Double?
    var isLiquid = false
    var warnings: [String] = []

    init(barcode: String? = nil) {
        self.barcode = barcode
    }

    init(parsed: ParsedLabel, barcode: String?) {
        self.barcode = barcode
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
}

struct LabelReviewForm: View {
    @State var draft: LabelDraft
    let rows: [String]
    let onSave: (Food) -> Void

    @Environment(\.modelContext) private var context
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
                Toggle("Drink (values per ml)", isOn: $draft.isLiquid)
            }

            Section {
                Picker("Values are", selection: $draft.basis) {
                    ForEach(LabelDraft.Basis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                number("Calories", $draft.values.kcal, unit: "kcal")
                number("Protein", $draft.values.protein, unit: "g")
                number("Carbs", $draft.values.carbs, unit: "g")
                number("Fat", $draft.values.fat, unit: "g")
            } header: {
                Text("Nutrition")
            } footer: {
                Text("Check these against the label. OCR can misread numbers.")
            }

            Section("Serving size") {
                HStack {
                    TextField("Optional", value: $draft.servingGrams, format: .number)
                        .keyboardType(.decimalPad)
                    Text(draft.isLiquid ? "ml" : "g").foregroundStyle(.secondary)
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
        .navigationTitle("Check label")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nameFocused = draft.name.isEmpty }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Save and choose portion")
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

    private func save() {
        guard let per100 = draft.per100 else { return }
        let candidate = FoodCandidate(
            id: "label:\(UUID().uuidString)",
            name: draft.name.trimmingCharacters(in: .whitespaces),
            brand: draft.brand.isEmpty ? nil : draft.brand,
            barcode: draft.barcode,
            per100: per100,
            servingGrams: draft.servingGrams,
            servingLabel: draft.servingGrams.map { "\($0.formatted()) \(draft.isLiquid ? "ml" : "g")" },
            isLiquid: draft.isLiquid,
            source: .label
        )
        let food = Food(candidate: candidate)
        context.insert(food)
        onSave(food)
    }
}
