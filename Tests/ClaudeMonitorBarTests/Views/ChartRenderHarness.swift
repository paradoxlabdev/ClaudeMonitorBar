import XCTest
import SwiftUI
@testable import ClaudeMonitorBar

/// Renders the real `UsageChartView` offscreen to PNGs so chart layout — axis label
/// truncation in particular — can be inspected without launching the app.
///
/// Opt-in, because it writes files and asserts nothing: `CHART_RENDER_DEBUG=1 swift test
/// --filter ChartRenderHarness`. Output goes to a temp directory, printed on completion.
///
/// Caveat: `ImageRenderer` does not draw the marks of a scrollable chart, so bars are
/// absent from the output. Gridlines, axes, and labels do render, which is what this is for.
final class ChartRenderHarness: XCTestCase {

    private var outputDir: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CHART_RENDER_DEBUG"] == "1",
            "set CHART_RENDER_DEBUG=1 to render chart PNGs"
        )
        outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chart-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    @MainActor
    private func render(_ view: some View, width: CGFloat, height: CGFloat, to name: String) throws {
        let renderer = ImageRenderer(
            content: view
                .frame(width: width, height: height)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        )
        renderer.scale = 3

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced nothing for \(name)")
            return
        }

        let file = outputDir.appendingPathComponent("\(name).png")
        try png.write(to: file)
        print("WROTE \(file.path)")
    }

    private func windows(_ kind: WindowKind, count: Int) -> [UsageWindow] {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return (0..<count).reversed().map { i in
            UsageWindow(
                kind: kind,
                end: now.addingTimeInterval(-Double(i) * kind.seconds),
                peak: [0.12, 0.45, 0.78, 0.95, 0.30][i % 5]
            )
        }
    }

    @MainActor
    func testRenderOneWindow() throws {
        let reset = Int(Date(timeIntervalSince1970: 1_800_000_000).timeIntervalSince1970)
        let view = UsageChartView(
            windows: windows(.fiveHour, count: 1) + windows(.sevenDay, count: 1),
            fiveHourReset: reset,
            sevenDayReset: reset,
            currentFiveHour: 0.15,
            currentSevenDay: 0.18
        )
        try render(view, width: 300, height: 200, to: "01-one-window")
    }

    @MainActor
    func testRenderManyWindows() throws {
        let reset = Int(Date(timeIntervalSince1970: 1_800_000_000).timeIntervalSince1970)
        let view = UsageChartView(
            windows: windows(.fiveHour, count: 20) + windows(.sevenDay, count: 10),
            fiveHourReset: reset,
            sevenDayReset: reset,
            currentFiveHour: 0.15,
            currentSevenDay: 0.18
        )
        try render(view, width: 300, height: 200, to: "02-many-windows")
    }
}
