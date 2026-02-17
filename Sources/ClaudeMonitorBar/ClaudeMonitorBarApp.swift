import SwiftUI

@main
struct ClaudeMonitorBarApp: App {
    @State private var sessionManager = SessionManager.shared
    @State private var prefs = AppPreferences.shared

    init() {
        NotificationManager.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SessionManager.shared.startMonitoring()
            UpdateChecker.shared.startPeriodicCheck()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
        } label: {
            let color: NSColor = switch sessionManager.statusColor {
            case .green: NSColor(red: 0.1, green: 0.85, blue: 0.2, alpha: 1.0)
            case .yellow: NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
            case .red: NSColor(red: 1.0, green: 0.2, blue: 0.15, alpha: 1.0)
            }
            Image(nsImage: menuBarIcon(color: color))
        }
        .menuBarExtraStyle(.window)
    }

    private var isDarkMenuBar: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var ringBackgroundColor: NSColor {
        let style = prefs.iconStyle
        switch style {
        case "light":
            return NSColor.white.withAlphaComponent(0.5)
        case "dark":
            return NSColor.black
        default: // "auto"
            return isDarkMenuBar
                ? NSColor.white.withAlphaComponent(0.3)
                : NSColor.black.withAlphaComponent(0.15)
        }
    }

    private var textColor: (NSColor) -> NSColor {
        { color in color }
    }

    private func menuBarIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            img.unlockFocus()
            return img
        }

        let center = CGPoint(x: 9, y: 9)
        let radius: CGFloat = 6.5
        let lineWidth: CGFloat = 2.5

        // Background ring
        ctx.setStrokeColor(ringBackgroundColor.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Progress arc
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        let startAngle = CGFloat.pi / 2
        let pct = max(sessionManager.overallPercentage, 0.05)
        let endAngle = startAngle - .pi * 2 * pct
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        ctx.strokePath()

        // ">_" text
        let font = NSFont.monospacedSystemFont(ofSize: 6, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let text = ">_" as NSString
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(x: (18 - textSize.width) / 2, y: (18 - textSize.height) / 2,
                              width: textSize.width, height: textSize.height)
        text.draw(in: textRect, withAttributes: attrs)

        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
