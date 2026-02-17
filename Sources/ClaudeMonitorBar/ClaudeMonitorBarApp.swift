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
            if let url = Bundle.module.url(forResource: "claude-icon", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: resizeForMenuBar(img))
            } else {
                Label("Claude", systemImage: "sparkle")
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func resizeForMenuBar(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        resized.isTemplate = false
        return resized
    }
}
