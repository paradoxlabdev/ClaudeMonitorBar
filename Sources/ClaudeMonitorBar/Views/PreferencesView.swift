import SwiftUI

struct PreferencesView: View {
    @Bindable var prefs = AppPreferences.shared

    var body: some View {
        Form {
            Section("Plan") {
                Picker("Plan tier:", selection: $prefs.planTier) {
                    ForEach(PlanTier.allCases, id: \.self) { tier in
                        Text(tier.rawValue).tag(tier)
                    }
                }
            }

            Section("General") {
                HStack {
                    Text("Refresh interval:")
                    TextField("", value: $prefs.refreshInterval, format: .number)
                        .frame(width: 50)
                    Text("seconds")
                }
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            }
        }
        .padding()
        .frame(width: 350)
    }
}
