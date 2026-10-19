import SwiftUI
import SwiftData
import Charts
import KcalCore

struct ProgressScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var recentEntries: [LogEntry]
    @State private var showingAddWeight = false

    init() {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _recentEntries = Query(filter: #Predicate<LogEntry> { $0.day >= since })
    }

    private var trend: [Double] { EnergyMath.trend(weights.map(\.kg)) }

    /// Average over the last 7 full days that have any entries. Days with nothing
    /// logged are skipped rather than counted as zero, which would flatter the number.
    private var averageIntake: Double? {
        let today = Calendar.current.startOfDay(for: .now)
        let byDay = Dictionary(grouping: recentEntries.filter { $0.day < today }, by: \.day)
        guard !byDay.isEmpty else { return nil }
        return byDay.values.map { $0.reduce(0) { $0 + $1.kcal } }.reduce(0, +) / Double(byDay.count)
    }

    /// Weekly change in the trend over the last ~4 weeks.
    private var weeklyRate: Double? {
        guard let last = weights.last, let lastTrend = trend.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-28 * 86_400)
        guard let i = weights.firstIndex(where: { $0.date >= cutoff }), i < weights.count - 1 else { return nil }
        let days = last.date.timeIntervalSince(weights[i].date) / 86_400
        guard days >= 7 else { return nil }
        return (lastTrend - trend[i]) / days * 7
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if weights.isEmpty {
                        BrandEmptyState(
                            title: "No weigh-ins yet",
                            message: Text("Weigh yourself a few times a week, same time of day. The trend line smooths out water swings.")
                        )
                    } else {
                        chart
                            .frame(height: 220)
                            .padding(.vertical, 8)
                    }
                }
                .listRowBackground(Theme.surface)

                Section("This week") {
                    row("Trend weight", trend.last.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" })
                    row("Weekly change", weeklyRate.map { "\($0 > 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(2)))) kg" })
                    row("Average intake", averageIntake.map { "\(Int($0.rounded())) kcal" })
                    row("Daily goal", "\(Int(settings.target.kcal)) kcal")
                }
                .listRowBackground(Theme.surface)

                if !weights.isEmpty {
                    Section("Weigh-ins") {
                        ForEach(weights.reversed()) { entry in
                            HStack {
                                Text(entry.date, format: .dateTime.weekday().day().month())
                                Spacer()
                                Text("\(entry.kg.formatted(.number.precision(.fractionLength(1)))) kg")
                                    .monospacedDigit()
                            }
                        }
                        .onDelete { offsets in
                            let reversed = Array(weights.reversed())
                            let removed = offsets.map { reversed[$0] }
                            let syncIDs = removed.compactMap(\.healthSyncID)
                            removed.forEach(context.delete)
                            Task { await health.deleteWeight(syncIDs: syncIDs) }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedList()
            .navigationTitle("Progress")
            .toolbar {
                Button("Add weight", systemImage: "plus") { showingAddWeight = true }
            }
            .sheet(isPresented: $showingAddWeight) {
                AddWeightSheet(lastKg: weights.last?.kg ?? settings.profile.weightKg)
                    .presentationDetents([.height(280)])
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(weights) { entry in
                PointMark(x: .value("Date", entry.date), y: .value("Weight", entry.kg))
                    .foregroundStyle(Theme.secondaryText)
                    .symbolSize(20)
            }
            ForEach(Array(zip(weights, trend)), id: \.0.id) { entry, value in
                LineMark(x: .value("Date", entry.date), y: .value("Trend", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "Not enough data")
                .foregroundStyle(value == nil ? .tertiary : .secondary)
                .monospacedDigit()
        }
    }
}

private struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @State private var kg: Double
    @State private var date = Date.now

    init(lastKg: Double) {
        _kg = State(initialValue: lastKg)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Weight", value: $kg, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                    Text("kg").foregroundStyle(Theme.secondaryText)
                }
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .themedList()
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        let entry = WeightEntry(date: date, kg: kg)
                        context.insert(entry)
                        Task { await health.save(entry) }
                        // Keep the goal calculation current with the latest weight.
                        if Calendar.current.isDateInToday(date) {
                            settings.profile.weightKg = kg
                        }
                        dismiss()
                    }
                    .disabled(kg < 30 || kg > 400)
                }
            }
        }
    }
}
