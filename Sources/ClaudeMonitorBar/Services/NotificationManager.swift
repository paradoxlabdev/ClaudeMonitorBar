import Foundation
import UserNotifications

enum NotificationManager {
    private static var notifiedThresholds: Set<String> = []
    private static var available = false

    static func requestPermission() {
        // UNUserNotificationCenter requires a valid bundle identifier
        guard Bundle.main.bundleIdentifier != nil else { return }
        available = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func checkAndNotify(limits: [UsageLimit]) {
        guard available, AppPreferences.shared.notificationsEnabled else { return }

        for limit in limits {
            let pct = Int(limit.percentage * 100)
            for threshold in [80, 90, 100] {
                let key = "\(limit.name)-\(threshold)"
                if pct >= threshold && !notifiedThresholds.contains(key) {
                    notifiedThresholds.insert(key)
                    send(title: "\(limit.name) at \(pct)%",
                         body: threshold == 100
                            ? "You've hit your \(limit.name.lowercased()). Resets \(limit.resetTimeFormatted)."
                            : "Approaching your \(limit.name.lowercased()). Resets \(limit.resetTimeFormatted).")
                }
            }
            // Reset notifications when usage drops (new window)
            if pct < 70 {
                notifiedThresholds = notifiedThresholds.filter { !$0.hasPrefix(limit.name) }
            }
        }
    }

    private static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
