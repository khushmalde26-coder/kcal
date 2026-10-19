import SwiftUI
import SwiftData
import KcalCore

/// Which add flow is open from Today.
enum AddFlow: String, Identifiable {
    case search, barcode, label, photo, homemade
    var id: String { rawValue }
}

struct TodayView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var flow: AddFlow?

    var body: some View {
        NavigationStack {
            DayLog(
                day: day,
                target: settings.target(activeEnergyKcal: health.activeEnergy(on: day)),
                showsActivity: settings.healthEnabled
            )
                .navigationTitle(title)
                .refreshable { await health.refreshActiveEnergy(on: day) }
                // Reload on day change, return to the app, or Health switched on, then follow
                // new workouts and movement live while Today is open.
                .task(id: ActivityKey(day: day, active: scenePhase == .active, health: settings.healthEnabled)) {
                    guard scenePhase == .active else { return }
                    await health.refreshActiveEnergy(on: day)
                    for await _ in health.activeEnergyChanges() {
                        await health.refreshActiveEnergy(on: day)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Previous day", systemImage: "chevron.left") { shift(-1) }
                        Button("Next day", systemImage: "chevron.right") { shift(1) }
                            .disabled(Calendar.current.isDateInToday(day))
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    QuickAddBar(flow: $flow)
                        .padding(.bottom, 8)
                }
                .sheet(item: $flow) { flow in
                    switch flow {
                    case .search: FoodSearchView(day: day, isSheet: true)
                    case .barcode: BarcodeFlow(day: day)
                    case .label: LabelFlow(day: day, barcode: nil)
                    case .photo: MealPhotoFlow(day: day)
                    case .homemade: HomemadeHub(day: day)
                    }
                }
        }
    }

    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func shift(_ days: Int) {
        withAnimation(.smooth) {
            day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
        }
    }
}

private struct ActivityKey: Equatable {
    var day: Date
    var active: Bool
    var health: Bool
}

/// The day's summary and meals. Split out so the @Query can depend on `day`.
private struct DayLog: View {
    let day: Date
    let target: DailyTarget
    let showsActivity: Bool
    @Query private var entries: [LogEntry]
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @State private var selected: LogEntry?

    init(day: Date, target: DailyTarget, showsActivity: Bool) {
        self.day = day
        self.target = target
        self.showsActivity = showsActivity
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == day }, sort: \LogEntry.timestamp)
    }

    private var totals: Nutrients {
        entries.reduce(.zero) { $0 + $1.nutrients }
    }

    var body: some View {
        List {
            Section {
                SummaryCard(eaten: totals, target: target, showsActivity: showsActivity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ForEach(Meal.allCases) { meal in
                let items = entries.filter { $0.meal == meal }
                Section {
                    if items.isEmpty {
                        Text("Nothing logged")
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(items) { entry in
                        Button { selected = entry } label: {
                            EntryRow(entry: entry)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { items[$0] }
                        let syncIDs = removed.compactMap(\.healthSyncID)
                        removed.forEach(context.delete)
                        Task { await health.deleteFood(syncIDs: syncIDs) }
                    }
                } header: {
                    HStack {
                        Label(meal.title, systemImage: meal.symbol)
                        Spacer()
                        Text("\(Int(items.reduce(0) { $0 + $1.kcal }.rounded())) kcal")
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .animation(.smooth, value: entries.count)
        .sheet(item: $selected) { entry in
            EntryDetailView(entry: entry, target: target)
        }
    }
}

private struct EntryRow: View {
    let entry: LogEntry

    private var subtitle: String {
        if entry.isQuickAdd { return "Calories only" }
        if !entry.ingredientNotes.isEmpty { return "Homemade" }
        return "\(Int(entry.grams.rounded())) \(entry.food?.unit ?? "g")"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.kcal.rounded()))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Floating glass controls for search, the camera flows, and homemade items with quick add.
/// Glass is used for controls only; content stays on plain backgrounds, per Apple's guidance.
private struct QuickAddBar: View {
    @Binding var flow: AddFlow?
    @Namespace private var glass
    private let photoAvailable = MealPhotoAnalyzer().isAvailable

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                button(.search, "Search", "magnifyingglass")
                button(.barcode, "Barcode", "barcode.viewfinder")
                button(.label, "Label", "text.viewfinder")
                if photoAvailable {
                    button(.photo, "Photo", "camera")
                }
                button(.homemade, "Homemade and quick add", "plus")
            }
        }
    }

    private func button(_ target: AddFlow, _ title: String, _ symbol: String) -> some View {
        Button {
            flow = target
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(target.rawValue, in: glass)
        .accessibilityLabel(title)
    }
}
