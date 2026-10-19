import SwiftUI
import SwiftData
import KcalCore

/// Photo of a plate → backend estimates foods and portions → user adjusts → log all.
/// Hidden from the UI until a backend endpoint is configured (see MealPhotoAnalyzer).
struct MealPhotoFlow: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var state: PhotoState = .capture
    @State private var meal = Meal.suggested()

    enum PhotoState {
        case capture
        case analyzing
        case review([MealPhotoItem])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Meal photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .capture:
            CameraPicker(onImage: { image in Task { await analyze(image) } }, onCancel: { dismiss() })
                .ignoresSafeArea()
        case .analyzing:
            ProgressView("Estimating your meal…")
        case .review(let items):
            review(items)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't estimate this meal", systemImage: "camera")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { state = .capture }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private func review(_ items: [MealPhotoItem]) -> some View {
        let binding = Binding<[MealPhotoItem]>(
            get: { items },
            set: { state = .review($0) }
        )
        let total = items.reduce(Nutrients.zero) { $0 + $1.per100.forPortion(grams: $1.grams) }
        return Form {
            Section {
                ForEach(binding) { $item in
                    VStack(alignment: .leading) {
                        TextField("Food", text: $item.name)
                            .font(.headline)
                        Stepper(value: $item.grams, in: 0...2000, step: 10) {
                            Text("\(Int(item.grams)) g · \(Int(item.per100.forPortion(grams: item.grams).kcal.rounded())) kcal")
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete { binding.wrappedValue.remove(atOffsets: $0) }
            } header: {
                Text("Estimated")
            } footer: {
                Text("Photo estimates can be off by 20% or more, mostly on portion size. Adjust the grams if you know better.")
            }
            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Button {
                logAll(items)
            } label: {
                Text("Log \(Int(total.kcal.rounded())) kcal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(items.isEmpty)
            .padding()
        }
    }

    private func analyze(_ image: UIImage) async {
        state = .analyzing
        do {
            state = .review(try await MealPhotoAnalyzer().analyze(image))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func logAll(_ items: [MealPhotoItem]) {
        for item in items where item.grams > 0 {
            let candidate = FoodCandidate(
                id: "photo:\(item.name.lowercased())",
                name: item.name,
                per100: item.per100,
                source: .mealPhoto
            )
            context.log(context.food(for: candidate), grams: item.grams, meal: meal, on: day)
        }
        dismiss()
    }
}
