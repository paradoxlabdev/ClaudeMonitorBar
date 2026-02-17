import Foundation

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

    /// Icon style: "auto", "light", "dark"
    var iconStyle: String = UserDefaults.standard.string(forKey: "iconStyle") ?? "dark" {
        didSet { UserDefaults.standard.set(iconStyle, forKey: "iconStyle") }
    }

    var launchAtLogin: Bool {
        get { launchAgentExists }
        set {
            if newValue {
                installLaunchAgent()
            } else {
                removeLaunchAgent()
            }
        }
    }

    // MARK: - LaunchAgent

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.claudemonitor.bar.plist")
    }

    private var launchAgentExists: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func installLaunchAgent() {
        // Find the .app bundle path
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else { return }

        let plist: [String: Any] = [
            "Label": "com.claudemonitor.bar",
            "ProgramArguments": ["\(appPath)/Contents/MacOS/ClaudeMonitorBar"],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let dir = launchAgentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: launchAgentURL)
        }
    }

    private func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
