import SwiftUI
import SwiftData
import KcalCore

/// Profile and goal form, shared by onboarding and settings.
struct GoalForm: View {
    @Binding var profile: EnergyProfile
    /// With Apple Health on, activity is measured rather than picked, and the plan
    /// shows the budget before any activity is added.
    var healthEnabled = false

    private var target: DailyTarget {
        EnergyMath.dailyTarget(profile, activeEnergyKcal: healthEnabled ? 0 : nil)
    }

    var body: some View {
        Section("About you") {
            Picker("Sex", selection: $profile.sex) {
                ForEach(BiologicalSex.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Age \(profile.age)", value: $profile.age, in: 16...100)
            measurement("Height", $profile.heightCm, unit: "cm")
            measurement("Weight", $profile.weightKg, unit: "kg")
            if healthEnabled {
                LabeledContent("Activity", value: "From Apple Health")
            } else {
                Picker("Activity", selection: $profile.activity) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
        }

        Section {
            Picker("Goal", selection: $profile.weeklyLossKg) {
                Text("Maintain").tag(0.0)
                Text("Lose 0.25 kg a week").tag(0.25)
                Text("Lose 0.5 kg a week").tag(0.5)
                Text("Lose 0.75 kg a week").tag(0.75)
                Text("Lose 1 kg a week").tag(1.0)
            }
        } header: {
            Text("Goal")
        } footer: {
            if let note = target.adjustmentNote {
                Text(note).foregroundStyle(.orange)
            }
        }

        Section {
            LabeledContent("Daily calories", value: "\(Int(target.kcal)) kcal\(healthEnabled ? " + activity" : "")")
            LabeledContent(healthEnabled ? "Resting + digestion" : "Maintenance", value: "\(Int(target.maintenance.rounded())) kcal")
            LabeledContent("Protein", value: "\(Int(target.macros.protein)) g")
            LabeledContent("Carbs", value: "\(Int(target.macros.carbs)) g")
            LabeledContent("Fat", value: "\(Int(target.macros.fat)) g")
        } header: {
            Text("Your plan")
        } footer: {
            Text("Estimated with the Mifflin-St Jeor equation. Real needs vary by a few hundred kcal; after 2 to 3 weeks your weight trend is the better guide."
                 + (healthEnabled ? " Activity calories from Apple Health are added through the day." : ""))
        }
    }

    private func measurement(_ title: String, _ value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                if HealthService.isAvailable {
                    Section {
                        Toggle(isOn: healthToggle) {
                            Label("Apple Health", systemImage: "heart.fill")
                                .foregroundStyle(.primary, .pink)
                        }
                        if settings.healthEnabled {
                            Picker("Count activity calories", selection: $settings.activeCredit) {
                                Text("50%").tag(0.5)
                                Text("75%").tag(0.75)
                                Text("100%").tag(1.0)
                            }
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Adds your active calories to the day's budget, saves the food you log and syncs weigh-ins. Watches often overestimate active calories, so Kcal counts 75% by default.")
                    }
                }
                GoalForm(profile: $settings.profile, healthEnabled: settings.healthEnabled)
                Section("Data sources") {
                    Link("Open Food Facts (ODbL)", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Link("USDA FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov")!)
                }
                Section {
                    Text("Kcal is not medical advice. Talk to a doctor before starting a diet if you are pregnant, under 18, or have a medical condition or a history of eating disorders.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var healthToggle: Binding<Bool> {
        Binding {
            settings.healthEnabled
        } set: { on in
            guard on else {
                settings.healthEnabled = false
                return
            }
            Task { settings.healthEnabled = await health.connect() }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @State private var profile = EnergyProfile()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("Let's set your daily target")
                            .font(.title2.bold())
                        Text("A few details give a starting estimate. You can change them any time in Settings.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                if HealthService.isAvailable {
                    Section {
                        if settings.healthEnabled {
                            Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task { settings.healthEnabled = await health.connect() }
                            } label: {
                                Label("Connect Apple Health", systemImage: "heart.fill")
                            }
                        }
                    } footer: {
                        Text("Optional. Your active calories raise the day's budget, and food and weigh-ins are saved to Health.")
                    }
                }
                GoalForm(profile: $profile, healthEnabled: settings.healthEnabled)
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                Button {
                    settings.profile = profile
                    let weight = WeightEntry(date: .now, kg: profile.weightKg)
                    context.insert(weight)
                    Task { await health.save(weight) }
                    settings.hasOnboarded = true
                } label: {
                    Text("Start tracking")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding()
            }
        }
    }
}
