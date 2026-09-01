import XCTest
import AppKit
@testable import ClaudeMonitorBar

/// Renders the real menu bar icon at 8× onto both menu bar backgrounds so the 6pt ">_"
/// glyph can be eyeballed — colour legibility at that size is not something a test asserts.
///
/// Opt-in: `ICON_RENDER_DEBUG=1 swift test --filter MenuBarIconRenderHarness`.
/// Output directory is printed on completion (override with `ICON_RENDER_DIR`).
final class MenuBarIconRenderHarness: XCTestCase {

    func testRenderIconMatrix() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ICON_RENDER_DEBUG"] == "1",
            "set ICON_RENDER_DEBUG=1 to render icon PNGs"
        )
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ICON_RENDER_DIR"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("icon-render").path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cases: [(String, Double, Double)] = [
            ("fresh-session-spent-week", 0.04, 0.93),   // the screenshot that prompted this
            ("fresh-session-warn-week", 0.04, 0.75),
            ("spent-session-fresh-week", 0.95, 0.10),
            ("both-fresh", 0.10, 0.20),
            ("both-spent", 0.95, 0.95)
        ]
        let backdrops: [(String, NSColor, NSColor)] = [
            ("dark", .black, NSColor.white.withAlphaComponent(0.3)),
            ("light", NSColor(white: 0.93, alpha: 1), NSColor.black.withAlphaComponent(0.15))
        ]

        let scale = CGFloat(Double(ProcessInfo.processInfo.environment["ICON_RENDER_SCALE"] ?? "8") ?? 8)
        let tile: CGFloat = 18 * scale
        let sheet = NSImage(size: NSSize(width: tile * CGFloat(cases.count),
                                         height: tile * CGFloat(backdrops.count)))
        sheet.lockFocus()
        for (row, backdrop) in backdrops.enumerated() {
            backdrop.1.setFill()
            NSRect(x: 0, y: CGFloat(row) * tile, width: tile * CGFloat(cases.count), height: tile).fill()
            for (col, c) in cases.enumerated() {
                let limits = [
                    UsageLimit(name: "Current session", utilization: c.1, resetTimestamp: nil),
                    UsageLimit(name: "Current week", utilization: c.2, resetTimestamp: nil)
                ]
                let ring = MenuBarIconColor.status(for: c.1)
                let icon = ClaudeMonitorBarApp.drawMenuBarIcon(
                    ringColor: ring,
                    glyphColor: MenuBarIconColor.glyph(limits: limits, ring: ring),
                    progress: c.1,
                    ringBackground: backdrop.2
                )
                NSGraphicsContext.current?.imageInterpolation = .none
                icon.draw(in: NSRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile,
                                     width: tile, height: tile))
            }
        }
        sheet.unlockFocus()

        let out = dir.appendingPathComponent("icon-matrix-\(Int(scale))x.png")
        guard let tiff = sheet.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return XCTFail("could not encode PNG") }
        try png.write(to: out)
        print("icon matrix (cols: \(cases.map(\.0).joined(separator: ", "))) -> \(out.path)")
    }
}
