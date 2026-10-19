import SwiftUI
import SwiftData
import KcalCore

struct FoodSearchView: View {
    let day: Date
    let isSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.lastUsedAt, order: .reverse) private var savedFoods: [Food]
    @State private var query = ""
    @State private var remote: [FoodCandidate] = []
    @State private var isSearching = false
    @State private var path: [FoodCandidate] = []
    @State private var loggedName: String?

    private let database = FoodDatabase()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    let favourites = savedFoods.filter(\.isFavorite)
                    if !favourites.isEmpty {
                        Section("Favourites") { rows(favourites) }
                    }
                    Section("Recent") {
                        if savedFoods.isEmpty {
                            ContentUnavailableView(
                                "No foods yet",
                                systemImage: "fork.knife",
                                description: Text("Search for a food, or scan a barcode or label from Today.")
                            )
                        }
                        rows(Array(savedFoods.prefix(30)))
                    }
                } else {
                    let local = savedFoods.filter { $0.name.localizedStandardContains(query) }
                    if !local.isEmpty {
                        Section("Your foods") { rows(local) }
                    }
                    Section {
                        ForEach(remote) { candidate in
                            NavigationLink(value: candidate) {
                                FoodRow(name: candidate.name, detail: detail(for: candidate))
                            }
                        }
                    } header: {
                        HStack {
                            Text("Database")
                            if isSearching { ProgressView().controlSize(.small) }
                        }
                    } footer: {
                        Text("Generic foods from USDA, packaged products from Open Food Facts.")
                    }
                }
            }
            .navigationTitle("Add food")
            .searchable(text: $query, prompt: "Banana, oat milk, chicken…")
            .onSubmit(of: .search) { Task { await searchRemote() } }
            // Remote search waits for a pause in typing; Open Food Facts allows ~10 searches a minute.
            .task(id: query) {
                remote = []
                guard query.count >= 3 else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await searchRemote()
            }
            .navigationDestination(for: FoodCandidate.self) { candidate in
                PortionView(candidate: candidate, existing: existing(for: candidate), day: day) {
                    logged(candidate.name)
                }
            }
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let loggedName {
                    Label("Logged \(loggedName)", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect()
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sensoryFeedback(.success, trigger: loggedName)
        }
    }

    private func rows(_ foods: [Food]) -> some View {
        ForEach(foods) { food in
            NavigationLink(value: food.candidate) {
                FoodRow(name: food.name, detail: food.subtitle, isFavorite: food.isFavorite)
            }
        }
    }

    private func existing(for candidate: FoodCandidate) -> Food? {
        savedFoods.first { $0.remoteID == candidate.id || $0.candidate.id == candidate.id }
    }

    private func detail(for c: FoodCandidate) -> String {
        [c.brand, "\(Int(c.per100.kcal.rounded())) kcal per 100 \(c.isLiquid ? "ml" : "g")"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func searchRemote() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        let results = await database.search(term)
        if term == query.trimmingCharacters(in: .whitespaces) { remote = results }
        isSearching = false
    }

    private func logged(_ name: String) {
        if isSheet {
            dismiss()
            return
        }
        path.removeAll()
        query = ""
        withAnimation(.smooth) { loggedName = name }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth) { loggedName = nil }
        }
    }
}

struct FoodRow: View {
    let name: String
    let detail: String
    var isFavorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(name).lineLimit(2)
                if isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
