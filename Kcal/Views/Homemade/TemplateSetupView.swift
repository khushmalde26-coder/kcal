import SwiftUI
import SwiftData
import KcalCore

/// First-time setup of a homemade item: one question per ingredient ("Which milk do you
/// use?", "How much?"), a running total, then save as e.g. "My coffee".
struct TemplateSetupView: View {
    let template: HomemadeTemplate
    let onSaved: (Recipe) -> Void

    @Environment(\.modelContext) private var context
    @Query private var stapleChoices: [StapleChoice]
    @State private var name: String
    @State private var drafts: [IngredientDraft]
    @State private var picking: StapleSlot?

    init(template: HomemadeTemplate, onSaved: @escaping (Recipe) -> Void) {
        self.template = template
        self.onSaved = onSaved
        _name = State(initialValue: template.savedName)
        _drafts = State(initialValue: template.items.map { item in
            switch item.part {
            case .staple(let slot):
                IngredientDraft(slot: slot, grams: item.grams, question: item.question,
                                portions: item.portions, isOptional: item.isOptional)
            case .generic(let name):
                IngredientDraft(generic: FoodDatabase.cofidCandidate(named: name).map { base in
                                    var base = base
                                    base.isLiquid = base.isLiquid || item.isLiquid
                                    return base
                                }, grams: item.grams,
                                question: item.question, portions: item.portions, isOptional: item.isOptional)
            }
        })
    }

    private var staples: StapleBook { StapleBook(choices: stapleChoices) }
    private var resolved: [ResolvedIngredient] { drafts.compactMap { $0.resolve(with: staples) } }
    private var total: Nutrients { RecipeMath.total(resolved.map { ($0.per100, $0.grams) }) }

    var body: some View {
        Form {
            ForEach($drafts) { $draft in
                let ingredient = draft.resolve(with: staples)
                Section {
                    if let slot = draft.slot {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient?.name ?? slot.title).lineLimit(2)
                                if staples.isDefault(slot) {
                                    Text("Typical UK \(slot.noun). Scan yours for exact numbers.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Change") { picking = slot }
                                .buttonStyle(.glass)
                        }
                    } else if let ingredient {
                        Text(ingredient.name)
                    }
                    IngredientAmount(draft: $draft, unit: ingredient?.unit ?? "g", choices: draft.choices(with: staples))
                } header: {
                    Text(draft.question ?? "")
                }
            }

            Section {
                TextField("Name", text: $name)
            } header: {
                Text("Save as")
            } footer: {
                Text("Changing your default \(drafts.compactMap(\.slot).first?.noun ?? "products") later updates future logs automatically.")
            }
        }
        .contentMargins(.bottom, 140, for: .scrollContent)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("\(Int(total.kcal.rounded())) kcal · P \(Int(total.protein.rounded())) g · C \(Int(total.carbs.rounded())) g · F \(Int(total.fat.rounded())) g")
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.numericText(value: total.kcal))
                    .animation(.smooth, value: total.kcal)
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
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || resolved.isEmpty)
            }
            .padding()
        }
        .sheet(item: $picking) { slot in
            FoodPicker(title: "Your \(slot.noun)", slot: slot) { food in
                context.setStaple(slot, food: food)
                picking = nil
            }
        }
    }

    private func save() {
        let recipe = Recipe(name: name.trimmingCharacters(in: .whitespaces), symbol: template.symbol, templateID: template.id)
        context.insert(recipe)
        context.save(drafts, into: recipe)
        onSaved(recipe)
    }
}
