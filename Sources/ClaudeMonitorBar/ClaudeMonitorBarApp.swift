import SwiftUI

@main
struct ClaudeMonitorBarApp: App {
    @State private var sessionManager = SessionManager.shared

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SessionManager.shared.startMonitoring()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
        } label: {
            Label("Claude", systemImage: "sparkle")
        }
        .menuBarExtraStyle(.window)
    }
}
