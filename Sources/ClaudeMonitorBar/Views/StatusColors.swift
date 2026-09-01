import SwiftUI
import AppKit

// The system red sits dark against the panel's near-black background — at the small
// sizes used for percentages, dots and banners it reads muddy rather than urgent.
// These are the same hue lifted in brightness so it stays legible on dark.
extension Color {
    static let statusRed = Color(nsColor: .statusRed)
}

extension NSColor {
    static let statusRed = NSColor(red: 1.0, green: 0.42, blue: 0.38, alpha: 1.0)
}

/// Colour policy for the menu bar icon.
///
/// The icon carries two independent signals in 18×18 points: the ring tracks the 5h
/// window, the ">_" glyph tracks the weekly limit. Driving both from one number — as it
/// did before — hid a nearly-spent week behind a freshly-reset session.
///
/// Thresholds match `UsageLimit.statusColor`, so a red glyph always lines up with a red
/// "Current week" dot in the panel below.
enum MenuBarIconColor {
    static let green = NSColor(red: 0.1, green: 0.85, blue: 0.2, alpha: 1.0)
    static let yellow = NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)

    static func status(for pct: Double) -> NSColor {
        if pct >= 0.9 { return .statusRed }
        if pct >= 0.7 { return yellow }
        return green
    }

    /// Weekly limit colour for the ">_" glyph, falling back to `ring` when there is no
    /// weekly figure yet — before the first fetch the icon then looks exactly as it always did.
    static func glyph(limits: [UsageLimit], ring: NSColor) -> NSColor {
        guard limits.count >= 2 else { return ring }
        return status(for: limits[1].percentage)
    }
}
