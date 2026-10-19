import SwiftUI
import SwiftData
import KcalCore

/// Photo of a nutrition panel → on-device OCR → user reviews the numbers →
/// product is saved (with its barcode if we came from a failed scan) → portion → logged.
struct LabelFlow: View {
    let day: Date
    let barcode: String?
    var embedded = false
    /// Pick mode: return the saved product instead of logging it.
    var onPick: ((Food) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var state: LabelState = .capture

    enum LabelState {
        case capture
        case reading
        case review(FoodDraft, rows: [String])
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
                    VStack(spacing: 10) {
                        Text("This product isn't in the database yet. Take a photo of its nutrition label to add it.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                        Button("Enter manually", systemImage: "square.and.pencil") {
                            state = .review(FoodDraft(barcode: barcode), rows: [])
                        }
                        .buttonStyle(.glass)
                    }
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
            FoodEditor(
                draft: draft,
                rows: rows,
                title: rows.isEmpty ? "New food" : "Check label",
                saveTitle: onPick == nil ? "Save and choose portion" : "Save",
                footer: rows.isEmpty ? nil : "Check these against the label. OCR can misread numbers."
            ) { draft in
                guard let candidate = draft.candidate(source: rows.isEmpty ? .custom : .label) else { return }
                let food = Food(candidate: candidate)
                context.insert(food)
                state = .portion(food)
            }
        case .portion(let food):
            if let onPick {
                PickConfirmView(candidate: food.candidate, existing: food, onPick: onPick)
            } else {
                PortionView(candidate: food.candidate, existing: food, day: day) { dismiss() }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't read the label", systemImage: "text.viewfinder")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { state = .capture }
                    .buttonStyle(.glassProminent)
                Button("Enter it manually") {
                    state = .review(FoodDraft(barcode: barcode), rows: [])
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
            state = .review(FoodDraft(parsed: parsed, barcode: barcode), rows: rows)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
