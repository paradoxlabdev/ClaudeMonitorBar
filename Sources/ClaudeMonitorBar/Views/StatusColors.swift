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
