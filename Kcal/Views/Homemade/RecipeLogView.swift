import SwiftUI
import SwiftData
import KcalCore

/// Log a homemade item. Ingredients use your current staples; amounts and products can
/// be changed for this time only without touching the saved recipe or your defaults.
struct RecipeLogView: View {
    let recipe: Recipe
    let day: Date
    let onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query private var stapleChoices: [StapleChoice]
    @State private var drafts: [IngredientDraft]
    @State private var servings: Double = 1
    @State private var meal = Meal.suggested()
    @State private var swapping: UUID?
    @State private var editing = false

    init(recipe: Recipe, day: Date, onLogged: @escaping () -> Void) {
        self.recipe = recipe
        self.day = day
        self.onLogged = onLogged
        _drafts = State(initialValue: recipe.sortedIngredients.map(IngredientDraft.init))
    }

    private var staples: StapleBook { StapleBook(choices: stapleChoices) }
    private var resolved: [ResolvedIngredient] { drafts.compactMap { $0.resolve(with: staples) } }
    private var portion: Nutrients {
        RecipeMath.total(resolved.map { ($0.per100, $0.grams) }).scaled(by: servings / max(recipe.servings, 0.01))
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Image(systemName: recipe.symbol)
                        .font(.title)
                        .foregroundStyle(.tint)
                    Text(portion.kcal, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: portion.kcal))
                    Text("kcal").foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        macro("Protein", portion.protein)
                        macro("Carbs", portion.carbs)
                        macro("Fat", portion.fat)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .animation(.smooth, value: portion)
            }

            Section {
                ForEach($drafts) { $draft in
                    let ingredient = draft.resolve(with: staples)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient?.name ?? "Missing food").lineLimit(2)
                                Text(ingredient.map { "\($0.amountText()) · \(Int($0.portion.kcal.rounded())) kcal" } ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Swap") { swapping = draft.id }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                        }
                        if editing {
                            IngredientAmount(draft: $draft, unit: ingredient?.unit ?? "g", choices: draft.choices(with: staples))
                        }
                    }
                }
            } header: {
                HStack {
                    Text("This time")
                    Spacer()
                    Button(editing ? "Done" : "Adjust amounts") { withAnimation { editing.toggle() } }
                        .font(.footnote)
                        .textCase(nil)
                }
            } footer: {
                Text("Swaps and amounts here apply to this log only.")
            }

            Section("How much") {
                Stepper(value: $servings, in: 0.5...10, step: 0.5) {
                    Text(servingsLabel)
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
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: log) {
                Text("Log \(Int(portion.kcal.rounded())) kcal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(resolved.isEmpty)
            .padding()
        }
        .sheet(item: Binding(get: { swapping.map(SwapTarget.init) }, set: { swapping = $0?.id })) { target in
            FoodPicker(title: "Swap for this time", slot: drafts.first { $0.id == target.id }?.slot) { food in
                if let index = drafts.firstIndex(where: { $0.id == target.id }) {
                    drafts[index].slot = nil
                    drafts[index].food = food
                }
                swapping = nil
            }
        }
    }

    private var servingsLabel: String {
        let n = servings.formatted(.number.precision(.fractionLength(0...1)))
        return recipe.servings > 1
            ? "\(n) of \(recipe.servings.formatted(.number.precision(.fractionLength(0...1)))) servings"
            : "\(n) × \(recipe.name)"
    }

    private func macro(_ name: String, _ grams: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(grams, format: .number.precision(.fractionLength(0...1))) g")
                .font(.headline.monospacedDigit())
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func log() {
        let entry = context.log(recipe, ingredients: resolved, servings: servings, meal: meal, on: day)
        Task { await health.save([entry]) }
        onLogged()
    }
}

private struct SwapTarget: Identifiable {
    let id: UUID
}
