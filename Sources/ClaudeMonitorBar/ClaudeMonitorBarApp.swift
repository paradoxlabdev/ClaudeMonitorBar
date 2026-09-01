import SwiftUI

@main
struct ClaudeMonitorBarApp: App {
    @State private var sessionManager = SessionManager.shared
    @State private var prefs = AppPreferences.shared

    init() {
        NotificationManager.setup()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SessionManager.shared.startMonitoring()
            UpdateChecker.shared.startPeriodicCheck()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
        } label: {
            if prefs.menuBarStyle == "percent" {
                Image(nsImage: percentIcon())
            } else {
                Image(nsImage: menuBarIcon(
                    ringColor: MenuBarIconColor.status(for: sessionManager.overallPercentage),
                    glyphColor: MenuBarIconColor.glyph(
                        limits: sessionManager.usageLimits,
                        ring: MenuBarIconColor.status(for: sessionManager.overallPercentage)
                    )
                ))
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Value of the limit selected to drive the percent menu bar text, clamped to 0...1.
    private var metricValue: Double {
        let raw: Double
        if prefs.menuBarMetric == "7d", sessionManager.usageLimits.count >= 2 {
            raw = sessionManager.usageLimits[1].percentage
        } else {
            raw = sessionManager.overallPercentage
        }
        guard raw.isFinite else { return 0 }
        return min(max(raw, 0), 1)
    }

    private func percentIcon() -> NSImage {
        let hasData = !sessionManager.usageLimits.isEmpty
        let pct = metricValue
        let text = (hasData ? "\(Int((pct * 100).rounded()))%" : "–") as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: hasData ? MenuBarIconColor.status(for: pct) : NSColor.gray
        ]
        let textSize = text.size(withAttributes: attrs)
        let size = NSSize(width: ceil(textSize.width) + 2, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        text.draw(at: NSPoint(x: 1, y: (size.height - textSize.height) / 2), withAttributes: attrs)
        img.unlockFocus()
        img.isTemplate = false
        return img
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

    private func menuBarIcon(ringColor: NSColor, glyphColor: NSColor) -> NSImage {
        Self.drawMenuBarIcon(
            ringColor: ringColor,
            glyphColor: glyphColor,
            progress: sessionManager.overallPercentage,
            ringBackground: ringBackgroundColor
        )
    }

    /// Free of app state so it can be rendered offscreen — the glyph is 6pt, and how it
    /// reads at that size is only answerable by looking at it.
    static func drawMenuBarIcon(
        ringColor: NSColor, glyphColor: NSColor, progress: Double, ringBackground: NSColor
    ) -> NSImage {
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
        ctx.setStrokeColor(ringBackground.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Progress arc — the 5h window
        ctx.setStrokeColor(ringColor.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        let startAngle = CGFloat.pi / 2
        let pct = max(progress, 0.05)
        let endAngle = startAngle - .pi * 2 * pct
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        ctx.strokePath()

        // ">_" text — the weekly limit
        let font = NSFont.monospacedSystemFont(ofSize: 6, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: glyphColor]
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
