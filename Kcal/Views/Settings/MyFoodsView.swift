import SwiftUI
import SwiftData
import KcalCore

/// Foods the user created or scanned from a label. Deleting a food keeps the
/// entries already logged with it, since they hold their own copy of the values.
struct MyFoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Food.name) private var allFoods: [Food]
    @State private var creating = false

    private var foods: [Food] { allFoods.filter(\.isUserCreated) }

    var body: some View {
        List {
            if foods.isEmpty {
                ContentUnavailableView(
                    "No foods of your own yet",
                    systemImage: "fork.knife",
                    description: Text("Foods you create or scan from a label appear here.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(foods) { food in
                NavigationLink {
                    EditFoodView(food: food)
                } label: {
                    FoodRow(name: food.name, detail: food.subtitle, isFavorite: food.isFavorite)
                }
            }
            .onDelete { offsets in
                let current = foods
                for index in offsets { context.delete(current[index]) }
            }
        }
        .navigationTitle("My foods")
        .toolbar {
            Button("Create food", systemImage: "plus") { creating = true }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                FoodEditor(draft: FoodDraft()) { draft in
                    if let candidate = draft.candidate(source: .custom) {
                        context.insert(Food(candidate: candidate))
                    }
                    creating = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { creating = false }
                    }
                }
            }
        }
    }
}

private struct EditFoodView: View {
    let food: Food
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FoodEditor(draft: FoodDraft(food: food), title: "Edit food", footer: "Changes apply to future logs. Entries already logged keep their values.") { draft in
            if let candidate = draft.candidate(source: food.source, id: food.remoteID) {
                food.update(from: candidate)
            }
            dismiss()
        }
    }
}
