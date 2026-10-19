import SwiftUI
import SwiftData

@main
struct KcalApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
        }
        .modelContainer(for: [Food.self, LogEntry.self, WeightEntry.self])
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.hasOnboarded {
            MainTabs()
        } else {
            OnboardingView()
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
