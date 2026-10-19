import SwiftUI
import SwiftData
import KcalCore

/// Choose a product by search, barcode or label photo, for a staple or a recipe ingredient.
/// Uses the normal add flows in pick mode, so they return the food instead of logging it.
struct FoodPicker: View {
    let title: String
    var slot: StapleSlot?
    let onPick: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.lastUsedAt, order: .reverse) private var foods: [Food]
    @State private var mode: Mode?

    enum Mode: String, Identifiable { case search, barcode, label; var id: String { rawValue } }

    /// Saved foods that look like this slot, e.g. milks you've logged before.
    private var suggestions: [Food] {
        guard let slot else { return [] }
        return Array(foods.filter { StapleSlot.match(productName: $0.name) == slot }.prefix(8))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Scan the barcode", systemImage: "barcode.viewfinder") { mode = .barcode }
                    Button("Photograph the nutrition label", systemImage: "text.viewfinder") { mode = .label }
                    Button("Search", systemImage: "magnifyingglass") { mode = .search }
                } footer: {
                    Text("Scanning the product you actually buy gives the most accurate numbers.")
                }
                .listRowBackground(Theme.surface)
                if !suggestions.isEmpty {
                    Section("Products you've used") {
                        ForEach(suggestions) { food in
                            Button { onPick(food) } label: {
                                FoodRow(name: food.name, detail: food.subtitle)
                            }
                            .tint(.primary)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedList()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(item: $mode) { mode in
                switch mode {
                case .search: FoodSearchView(day: .now, isSheet: true, onPick: onPick)
                case .barcode: BarcodeFlow(day: .now, onPick: onPick)
                case .label: LabelFlow(day: .now, barcode: nil, onPick: onPick)
                }
            }
        }
    }
}

/// Shown instead of the portion screen when picking: the product's values and "Use this".
struct PickConfirmView: View {
    let candidate: FoodCandidate
    let existing: Food?
    let onPick: (Food) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name).font(.title3.bold())
                    if let brand = candidate.brand {
                        Text(brand).foregroundStyle(Theme.secondaryText)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listRowBackground(Theme.surface)
            Section(candidate.isPerPortion ? "Per portion" : "Per 100 \(candidate.unit)") {
                row("Calories", candidate.per100.kcal, "kcal")
                row("Protein", candidate.per100.protein, "g")
                row("Carbs", candidate.per100.carbs, "g")
                row("Fat", candidate.per100.fat, "g")
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .navigationTitle("Use this product?")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onPick(existing ?? context.food(for: candidate))
            } label: {
                Text("Use this")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(Theme.onTint)
            .padding()
        }
    }

    private func row(_ name: String, _ value: Double, _ unit: String) -> some View {
        LabeledContent(name, value: "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
    }
}
