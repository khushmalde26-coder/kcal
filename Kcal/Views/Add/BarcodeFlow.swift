import SwiftUI
import SwiftData
import KcalCore

/// Scan → look up locally, then Open Food Facts → portion.
/// Products that aren't in the database hand over to the label scanner with the
/// barcode attached, so the next scan of that product finds it locally.
struct BarcodeFlow: View {
    let day: Date
    /// Pick mode: return the product instead of logging it.
    var onPick: ((Food) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var state: ScanState = .scanning
    @State private var manualCode = ""

    enum ScanState {
        case scanning
        case lookingUp(String)
        case found(FoodCandidate, Food?)
        case notFound(String)
        case failed(String, String)
    }

    var body: some View {
        NavigationStack {
            content
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
        case .scanning:
            scanner
        case .lookingUp:
            ProgressView("Looking up product…")
                .navigationTitle("Barcode")
        case .found(let candidate, let food):
            if let onPick {
                PickConfirmView(candidate: candidate, existing: food, onPick: onPick)
            } else {
                PortionView(candidate: candidate, existing: food, day: day) { dismiss() }
            }
        case .notFound(let code):
            LabelFlow(day: day, barcode: code, embedded: true, onPick: onPick)
        case .failed(let code, let message):
            ContentUnavailableView {
                Label("Couldn't look that up", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await lookUp(code) } }
                    .buttonStyle(.glassProminent)
                Button("Scan the label instead") { state = .notFound(code) }
                    .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if BarcodeScanner.isAvailable {
            BarcodeScanner { code in Task { await lookUp(code) } }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text("Point the camera at a barcode")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect()
                        .padding(.bottom, 40)
                }
        } else {
            Form {
                Section {
                    TextField("Barcode number", text: $manualCode)
                        .keyboardType(.numberPad)
                    Button("Look up") { Task { await lookUp(manualCode) } }
                        .disabled(manualCode.count < 8)
                } footer: {
                    Text("Camera scanning isn't available on this device.")
                }
            }
            .navigationTitle("Barcode")
        }
    }

    private func lookUp(_ code: String) async {
        if let saved = context.existingFood(barcode: code) {
            state = .found(saved.candidate, saved)
            return
        }
        state = .lookingUp(code)
        do {
            if let candidate = try await FoodDatabase().product(barcode: code) {
                state = .found(candidate, nil)
            } else {
                state = .notFound(code)
            }
        } catch {
            state = .failed(code, error.localizedDescription)
        }
    }
}
