import XCTest
@testable import ClaudeMonitorBar

final class DebugLogParserTests: XCTestCase {
    func testExtractTokenCount() {
        let logLine = "2026-02-17T06:28:40.092Z [DEBUG] autocompact: tokens=38125 threshold=167000"
        let tokens = DebugLogParser.extractTokenCount(from: logLine)
        XCTAssertEqual(tokens, 38125)
    }

    func testExtractTokenCountFromStatusLine() {
        let logLine = #"  next: "✶ Forging… (47s · ↑ 2.0k tokens)""#
        let tokens = DebugLogParser.extractTokenCountFromStatus(logLine)
        XCTAssertEqual(tokens, 2000)
    }

    func testNoTokensInLine() {
        let logLine = "2026-02-17 [DEBUG] some other log"
        let tokens = DebugLogParser.extractTokenCount(from: logLine)
        XCTAssertNil(tokens)
    }

    func testParseSessionIdFromFilename() {
        let filename = "5fe7a1c8-7255-43eb-983c-85e5d15287fa.txt"
        let sessionId = DebugLogParser.sessionId(from: filename)
        XCTAssertEqual(sessionId, "5fe7a1c8-7255-43eb-983c-85e5d15287fa")
    }
}
