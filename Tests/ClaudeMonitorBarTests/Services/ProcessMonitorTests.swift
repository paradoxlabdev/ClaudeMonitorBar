import XCTest
@testable import ClaudeMonitorBar

final class ProcessMonitorTests: XCTestCase {
    func testParseProcessLine() {
        let line = "28018 claude ALACRITTY_WINDOW_ID=12884902035"
        let result = ProcessMonitor.parseProcessLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pid, 28018)
    }

    func testParseInvalidLine() {
        let result = ProcessMonitor.parseProcessLine("not a process")
        XCTAssertNil(result)
    }
}
