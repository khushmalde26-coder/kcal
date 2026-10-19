import SwiftUI
import SwiftData
import KcalCore

/// The products the user buys, used by homemade items.
struct StaplesView: View {
    @Environment(\.modelContext) private var context
    @Query private var stapleChoices: [StapleChoice]
    @State private var picking: StapleSlot?

    private var staples: StapleBook { StapleBook(choices: stapleChoices) }

    var body: some View {
        List {
            Section {
                ForEach(StapleSlot.allCases) { slot in
                    Button { picking = slot } label: {
                        HStack(spacing: 12) {
                            Image(systemName: slot.symbol)
                                .frame(width: 28)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.title)
                                Text(subtitle(slot))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                    .swipeActions {
                        if !staples.isDefault(slot) {
                            Button("Reset") { context.setStaple(slot, food: nil) }
                        }
                    }
                }
            } footer: {
                Text("Scan the milk, bread and other products you buy and your homemade items use their exact values. Until then, a typical UK product is used.")
            }
        }
        .navigationTitle("My staples")
        .sheet(item: $picking) { slot in
            FoodPicker(title: "Your \(slot.noun)", slot: slot) { food in
                context.setStaple(slot, food: food)
                picking = nil
            }
        }
    }

    private func subtitle(_ slot: StapleSlot) -> String {
        if let food = staples.food(for: slot) {
            return [food.name, food.brand].compactMap { $0 }.joined(separator: " · ")
        }
        return "Default: \(slot.fallbackCoFIDName)"
    }
}
