import Foundation

@Observable
class AppPreferences {
    static let shared = AppPreferences()

    var planTier: PlanTier {
        get {
            // Auto-detect from Keychain on first run
            if !UserDefaults.standard.bool(forKey: "planTierSet") {
                if let detected = PlanTier.detectFromKeychain() {
                    UserDefaults.standard.set(detected.rawValue, forKey: "planTier")
                    UserDefaults.standard.set(true, forKey: "planTierSet")
                    return detected
                }
            }
            guard let raw = UserDefaults.standard.string(forKey: "planTier"),
                  let tier = PlanTier(rawValue: raw) else { return .pro }
            return tier
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "planTier")
            UserDefaults.standard.set(true, forKey: "planTierSet")
        }
    }

    var refreshInterval: Double {
        get { UserDefaults.standard.double(forKey: "refreshInterval").nonZero ?? 10.0 }
        set { UserDefaults.standard.set(newValue, forKey: "refreshInterval") }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
