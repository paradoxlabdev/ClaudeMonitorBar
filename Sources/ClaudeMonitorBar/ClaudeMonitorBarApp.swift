import SwiftUI
import ServiceManagement

@main
struct ClaudeMonitorBarApp: App {
    @State private var sessionManager = SessionManager.shared

    init() {
        NotificationManager.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SessionManager.shared.startMonitoring()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
        } label: {
            let color: NSColor = switch sessionManager.statusColor {
            case .green: .systemGreen
            case .yellow: .systemYellow
            case .red: .systemRed
            }
            Image(nsImage: menuBarIcon(color: color))
        }
        .menuBarExtraStyle(.window)
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
        let lineWidth: CGFloat = 2.0

        // Background ring
        ctx.setStrokeColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
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
