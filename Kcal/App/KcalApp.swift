import SwiftUI
import SwiftData

@main
struct KcalApp: App {
    @State private var settings: AppSettings
    @State private var health: HealthService

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _health = State(initialValue: HealthService(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(health)
        }
        .modelContainer(for: [Food.self, LogEntry.self, WeightEntry.self])
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
