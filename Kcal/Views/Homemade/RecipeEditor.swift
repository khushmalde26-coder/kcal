import SwiftUI
import SwiftData
import KcalCore

/// Build a homemade item from scratch, or edit a saved one: staples (which follow your
/// defaults) and specific foods, each with an amount.
struct RecipeEditor: View {
    let recipe: Recipe?
    let onSaved: (Recipe) -> Void

    @Environment(\.modelContext) private var context
    @Query private var stapleChoices: [StapleChoice]
    @State private var name: String
    @State private var symbol: String
    @State private var servings: Double
    @State private var drafts: [IngredientDraft]
    @State private var pickingFood = false

    static let symbols = [
        "fork.knife", "cup.and.saucer.fill", "mug.fill", "frying.pan.fill", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "carrot.fill", "fish.fill", "leaf.fill", "wineglass.fill",
    ]

    init(recipe: Recipe?, onSaved: @escaping (Recipe) -> Void) {
        self.recipe = recipe
        self.onSaved = onSaved
        _name = State(initialValue: recipe?.name ?? "")
        _symbol = State(initialValue: recipe?.symbol ?? "fork.knife")
        _servings = State(initialValue: recipe?.servings ?? 1)
        _drafts = State(initialValue: recipe?.sortedIngredients.map(IngredientDraft.init) ?? [])
    }

    private var staples: StapleBook { StapleBook(choices: stapleChoices) }
    private var total: Nutrients {
        RecipeMath.total(drafts.compactMap { $0.resolve(with: staples) }.map { ($0.per100, $0.grams) })
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Sunday pancakes", text: $name)
                Picker("Icon", selection: $symbol) {
                    ForEach(Self.symbols, id: \.self) { Image(systemName: $0).tag($0) }
                }
                Stepper(value: $servings, in: 1...20) {
                    Text("Makes \(Int(servings)) serving\(servings == 1 ? "" : "s")")
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach($drafts) { $draft in
                    let ingredient = draft.resolve(with: staples)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if let slot = draft.slot {
                                Image(systemName: slot.symbol).foregroundStyle(Theme.secondaryText)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient?.name ?? "Missing food").lineLimit(2)
                                if let slot = draft.slot {
                                    Text("Your \(slot.noun)").font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        IngredientAmount(draft: $draft, unit: ingredient?.unit ?? "g", choices: draft.choices(with: staples))
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }

                Menu {
                    Section("Your staples") {
                        ForEach(StapleSlot.allCases) { slot in
                            Button(slot.title, systemImage: slot.symbol) {
                                drafts.append(IngredientDraft(slot: slot, grams: slot.portions().first?.grams ?? 50,
                                                              unitLabel: slot.portions().first?.label))
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                    Button("Any food…", systemImage: "magnifyingglass") { pickingFood = true }
                } label: {
                    Label("Add ingredient", systemImage: "plus.circle")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Staples follow your default products in Settings › My staples.")
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .contentMargins(.bottom, 140, for: .scrollContent)
        .navigationTitle(recipe == nil ? "Build your own" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                let perServing = RecipeMath.perServing(total, servings: servings)
                Text("\(Int(perServing.kcal.rounded())) kcal per serving")
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect()
                Button(action: save) {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(Theme.onTint)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || drafts.isEmpty)
            }
            .padding()
        }
        .sheet(isPresented: $pickingFood) {
            FoodPicker(title: "Add a food") { food in
                drafts.append(IngredientDraft(food: food, grams: food.servingGrams ?? 100, unitLabel: food.servingLabel))
                pickingFood = false
            }
        }
    }

    private func save() {
        let target = recipe ?? {
            let new = Recipe(name: "", symbol: symbol)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.symbol = symbol
        target.servings = servings
        context.save(drafts, into: target)
        onSaved(target)
    }
}
