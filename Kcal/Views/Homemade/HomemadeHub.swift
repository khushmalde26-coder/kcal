import SwiftUI
import SwiftData
import KcalCore

/// Today's "+" sheet: saved homemade items, templates to set one up, build your own,
/// and quick add.
struct HomemadeHub: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Recipe.useCount, order: .reverse), SortDescriptor(\Recipe.lastUsedAt, order: .reverse)])
    private var recipes: [Recipe]
    @State private var path = NavigationPath()

    enum Route: Hashable {
        case template(String)
        case newRecipe
        case quickAdd
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !recipes.isEmpty {
                    Section("Your homemade") {
                        ForEach(recipes) { recipe in
                            NavigationLink(value: recipe) {
                                Label(recipe.name, systemImage: recipe.symbol)
                            }
                        }
                    }
                }

                Section {
                    ForEach(HomemadeTemplate.all) { template in
                        NavigationLink(value: Route.template(template.id)) {
                            Label(template.name, systemImage: template.symbol)
                        }
                    }
                    NavigationLink(value: Route.newRecipe) {
                        Label("Build your own", systemImage: "plus.square.on.square")
                    }
                } header: {
                    Text(recipes.isEmpty ? "Set up something you make often" : "Set up another")
                } footer: {
                    Text("Built from the milk, bread and other products you buy. Set them in Settings › My staples, or as you go.")
                }

                Section {
                    NavigationLink(value: Route.quickAdd) {
                        Label("Quick add calories", systemImage: "number")
                    }
                }
            }
            .navigationTitle("Homemade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeLogView(recipe: recipe, day: day) { dismiss() }
            }
            .navigationDestination(for: FoodCandidate.self) { candidate in
                PortionView(candidate: candidate, existing: nil, day: day) { dismiss() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .template(let id):
                    if let template = HomemadeTemplate.all.first(where: { $0.id == id }) {
                        TemplateSetupView(template: template) { recipe in
                            path = NavigationPath([recipe])
                        }
                    }
                case .newRecipe:
                    RecipeEditor(recipe: nil) { recipe in
                        path = NavigationPath([recipe])
                    }
                case .quickAdd:
                    QuickAddView(day: day, path: $path) { dismiss() }
                }
            }
        }
    }
}

/// A calorie number, optionally with macros. Typing a name suggests matching
/// homemade items and saved foods.
struct QuickAddView: View {
    let day: Date
    @Binding var path: NavigationPath
    let onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query(sort: \Recipe.useCount, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \Food.lastUsedAt, order: .reverse) private var foods: [Food]
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var name = ""
    @State private var meal = Meal.suggested()
    @FocusState private var kcalFocused: Bool

    private var term: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Calories", value: $kcal, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                        .focused($kcalFocused)
                    Text("kcal").foregroundStyle(.secondary)
                }
                TextField("Name (optional)", text: $name)
            }

            if term.count >= 2 {
                let matchingRecipes = recipes.filter { $0.name.localizedStandardContains(term) }.prefix(3)
                let matchingFoods = foods.filter { $0.name.localizedStandardContains(term) }.prefix(3)
                if !matchingRecipes.isEmpty || !matchingFoods.isEmpty {
                    Section("Did you mean") {
                        ForEach(Array(matchingRecipes)) { recipe in
                            Button { path.append(recipe) } label: {
                                Label(recipe.name, systemImage: recipe.symbol)
                            }
                        }
                        ForEach(Array(matchingFoods)) { food in
                            Button { path.append(food.candidate) } label: {
                                FoodRow(name: food.name, detail: food.subtitle)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }

            Section("Macros (optional)") {
                grams("Protein", $protein)
                grams("Carbs", $carbs)
                grams("Fat", $fat)
            }

            Section {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Quick add")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { kcalFocused = true }
        .safeAreaInset(edge: .bottom) {
            Button(action: log) {
                Text(kcal.map { "Log \(Int($0)) kcal" } ?? "Log")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled((kcal ?? 0) <= 0)
            .padding()
        }
    }

    private func grams(_ title: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text("g").foregroundStyle(.secondary)
        }
    }

    private func log() {
        guard let kcal, kcal > 0 else { return }
        let nutrients = Nutrients(kcal: kcal, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
        let entry = context.quickAdd(name: term.isEmpty ? "Quick add" : term, nutrients: nutrients, meal: meal, on: day)
        Task { await health.save([entry]) }
        onLogged()
    }
}

/// Amount editing for one ingredient: chips plus a number field.
struct IngredientAmount: View {
    @Binding var draft: IngredientDraft
    let unit: String
    let choices: [PortionChoice]

    var body: some View {
        if !choices.isEmpty || draft.isOptional {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    if draft.isOptional {
                        chip("None", 0)
                    }
                    ForEach(choices, id: \.self) { choice in
                        chip(choice.label, choice.grams)
                    }
                }
            }
        }
        HStack {
            Text("Amount")
            Spacer()
            TextField("Amount", value: $draft.grams, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func chip(_ label: String, _ grams: Double) -> some View {
        let selected = abs(draft.grams - grams) < 0.01
        return Button(label) {
            draft.grams = grams
            draft.unitLabel = grams > 0 ? label : nil
        }
        .buttonStyle(.glass)
        .tint(selected ? .accentColor : nil)
        .fontWeight(selected ? .semibold : .regular)
    }
}
