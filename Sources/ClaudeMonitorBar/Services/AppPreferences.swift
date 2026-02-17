import Foundation
import ServiceManagement

@Observable
class AppPreferences {
    static let shared = AppPreferences()

    var planTier: PlanTier {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "planTier"),
                  let tier = PlanTier(rawValue: raw) else { return .pro }
            return tier
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "planTier")
        }
    }

    /// Auto-refresh interval in minutes
    var refreshInterval: Double {
        get { UserDefaults.standard.double(forKey: "refreshInterval").nonZero ?? 5.0 }
        set {
            UserDefaults.standard.set(newValue, forKey: "refreshInterval")
            SessionManager.shared.startAutoRefresh()
        }
    }

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — requires .app bundle
            }
        }
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
