import XCTest
import AppKit
@testable import ClaudeMonitorBar

/// The menu bar icon carries two independent signals: the ring tracks the 5h window,
/// the ">_" glyph tracks the weekly limit. These pin the mapping from percentages to
/// colours, and the fallback that keeps a data-less icon looking as it always did.
final class MenuBarIconColorTests: XCTestCase {

    /// NSColor equality is colour-space sensitive; compare components instead.
    private func assertSameColor(
        _ a: NSColor, _ b: NSColor, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else {
            return XCTFail("colour not convertible to sRGB", file: file, line: line)
        }
        XCTAssertEqual(a.redComponent, b.redComponent, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(a.greenComponent, b.greenComponent, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(a.blueComponent, b.blueComponent, accuracy: 0.001, message, file: file, line: line)
    }

    private func limits(fiveHour: Double, sevenDay: Double) -> [UsageLimit] {
        [
            UsageLimit(name: "Current session", utilization: fiveHour, resetTimestamp: nil),
            UsageLimit(name: "Current week", utilization: sevenDay, resetTimestamp: nil)
        ]
    }

    // MARK: - Thresholds

    func testStatusColorThresholdsMatchPanelDots() {
        assertSameColor(MenuBarIconColor.status(for: 0.0), MenuBarIconColor.green, "0% is green")
        assertSameColor(MenuBarIconColor.status(for: 0.69), MenuBarIconColor.green, "below 70% is green")
        assertSameColor(MenuBarIconColor.status(for: 0.7), MenuBarIconColor.yellow, "70% is the yellow boundary")
        assertSameColor(MenuBarIconColor.status(for: 0.89), MenuBarIconColor.yellow, "below 90% is yellow")
        assertSameColor(MenuBarIconColor.status(for: 0.9), .statusRed, "90% is the red boundary")
        assertSameColor(MenuBarIconColor.status(for: 1.0), .statusRed, "100% is red")
    }

    // MARK: - Glyph colour

    func testGlyphTracksWeeklyLimitNotTheFiveHourWindow() {
        // The case that prompted this: session barely touched, week nearly spent.
        let glyph = MenuBarIconColor.glyph(limits: limits(fiveHour: 0.04, sevenDay: 0.93),
                                           ring: MenuBarIconColor.green)
        assertSameColor(glyph, .statusRed, "93% weekly must turn the glyph red even at 4% session")
    }

    func testGlyphIsGreenWhileWeeklyHasHeadroom() {
        let glyph = MenuBarIconColor.glyph(limits: limits(fiveHour: 0.95, sevenDay: 0.10),
                                           ring: .statusRed)
        assertSameColor(glyph, MenuBarIconColor.green, "10% weekly stays green under a red ring")
    }

    func testGlyphGoesYellowInTheWarnBand() {
        let glyph = MenuBarIconColor.glyph(limits: limits(fiveHour: 0.0, sevenDay: 0.75),
                                           ring: MenuBarIconColor.green)
        assertSameColor(glyph, MenuBarIconColor.yellow, "75% weekly is the warn band")
    }

    func testGlyphClampsOutOfRangeWeeklyValues() {
        let over = MenuBarIconColor.glyph(limits: limits(fiveHour: 0.0, sevenDay: 1.4),
                                          ring: MenuBarIconColor.green)
        assertSameColor(over, .statusRed, "utilisation above 1.0 is still red")
    }

    // MARK: - Fallback before the first fetch

    func testGlyphFallsBackToRingColorWithoutData() {
        let ring = MenuBarIconColor.green
        assertSameColor(MenuBarIconColor.glyph(limits: [], ring: ring), ring,
                        "no limits yet: icon looks exactly as it did before")
    }

    func testGlyphFallsBackToRingColorWhenWeeklyIsMissing() {
        let ring = MenuBarIconColor.yellow
        let sessionOnly = [UsageLimit(name: "Current session", utilization: 0.8, resetTimestamp: nil)]
        assertSameColor(MenuBarIconColor.glyph(limits: sessionOnly, ring: ring), ring,
                        "only a 5h limit: no weekly signal to show")
    }
}
