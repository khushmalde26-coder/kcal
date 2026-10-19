import SwiftUI
import SwiftData
import KcalCore

/// Profile and goal form, shared by onboarding and settings.
struct GoalForm: View {
    @Binding var profile: EnergyProfile

    private var target: DailyTarget { EnergyMath.dailyTarget(profile) }

    var body: some View {
        Section("About you") {
            Picker("Sex", selection: $profile.sex) {
                ForEach(BiologicalSex.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Age \(profile.age)", value: $profile.age, in: 16...100)
            measurement("Height", $profile.heightCm, unit: "cm")
            measurement("Weight", $profile.weightKg, unit: "kg")
            Picker("Activity", selection: $profile.activity) {
                ForEach(ActivityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
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
            LabeledContent("Daily calories", value: "\(Int(target.kcal)) kcal")
            LabeledContent("Maintenance", value: "\(Int(target.maintenance.rounded())) kcal")
            LabeledContent("Protein", value: "\(Int(target.macros.protein)) g")
            LabeledContent("Carbs", value: "\(Int(target.macros.carbs)) g")
            LabeledContent("Fat", value: "\(Int(target.macros.fat)) g")
        } header: {
            Text("Your plan")
        } footer: {
            Text("Estimated with the Mifflin-St Jeor equation. Real needs vary by a few hundred kcal; after 2 to 3 weeks your weight trend is the better guide.")
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

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                GoalForm(profile: $settings.profile)
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
}

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
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
                GoalForm(profile: $profile)
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                Button {
                    settings.profile = profile
                    context.insert(WeightEntry(date: .now, kg: profile.weightKg))
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
