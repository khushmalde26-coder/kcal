import SwiftUI
import SwiftData
import KcalCore

@main
struct KcalApp: App {
    @State private var settings: AppSettings
    @State private var health: HealthService

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _health = State(initialValue: HealthService(settings: settings))
        Theme.applyNavigationAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(health)
                .tint(Theme.ringGoal)
                .foregroundStyle(Theme.text)
        }
        .modelContainer(for: [Food.self, LogEntry.self, WeightEntry.self, StapleChoice.self, Recipe.self, RecipeIngredient.self])
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if settings.hasOnboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        #if DEBUG
        // For screenshots: KCAL_SEED_KCAL=900 replaces today's log with one quick add.
        .task {
            guard let kcal = ProcessInfo.processInfo.environment["KCAL_SEED_KCAL"].flatMap(Double.init) else { return }
            let today = Calendar.current.startOfDay(for: .now)
            try? context.delete(model: LogEntry.self, where: #Predicate { $0.day == today })
            if kcal > 0 { context.quickAdd(name: "Lunch out", nutrients: Nutrients(kcal: kcal, protein: kcal * 0.05, carbs: kcal * 0.11, fat: kcal * 0.035), meal: .lunch, on: .now) }
        }
        #endif
        // Ask for any Health types added since the user connected (iOS only shows new ones).
        .task {
            if settings.healthEnabled { _ = await health.connect() }
        }
        // Pick up weigh-ins from scales and other apps whenever Kcal comes forward.
        .task(id: scenePhase == .active && settings.healthEnabled) {
            guard scenePhase == .active else { return }
            await health.importWeights(into: context)
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "flame.fill") {
                TodayView()
            }
            Tab("Progress", systemImage: "chart.line.downtrend.xyaxis") {
                ProgressScreen()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
            // iOS 26 places the search tab on its own in the glass tab bar.
            Tab(role: .search) {
                FoodSearchView(day: .now, isSheet: false)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
