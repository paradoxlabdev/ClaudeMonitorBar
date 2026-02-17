import Foundation
import UserNotifications

/// Delegate that allows notifications to show when the app is in the foreground.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum NotificationManager {
    private static var notifiedThresholds: Set<String> = []

    static func setup() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func checkAndNotify(limits: [UsageLimit]) {
        guard AppPreferences.shared.notificationsEnabled else { return }

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

    static func forceTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Claude Monitor Bar"
        content.body = "Test notification — notifications are working!"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                print("[NotificationManager] Error: \(error)")
            } else {
                print("[NotificationManager] Test notification scheduled")
            }
        }
    }

    private static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
