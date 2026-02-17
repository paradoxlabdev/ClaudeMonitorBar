import XCTest
@testable import ClaudeMonitorBar

final class StatsCacheReaderTests: XCTestCase {
    func testParseStatsCache() throws {
        let json = """
        {
            "version": 2,
            "lastComputedDate": "2026-02-16",
            "dailyActivity": [
                {"date": "2026-02-16", "messageCount": 100, "sessionCount": 2, "toolCallCount": 10}
            ],
            "dailyModelTokens": [
                {"date": "2026-02-16", "tokensByModel": {"claude-opus-4-6": 50000, "claude-sonnet-4-5-20250929": 10000}}
            ],
            "modelUsage": {
                "claude-opus-4-6": {
                    "inputTokens": 1000,
                    "outputTokens": 5000,
                    "cacheReadInputTokens": 100000,
                    "cacheCreationInputTokens": 2000
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let stats = try StatsCacheReader.parse(data: data)
        XCTAssertEqual(stats.dailyActivity.count, 1)
        XCTAssertEqual(stats.dailyActivity[0].messageCount, 100)
        XCTAssertEqual(stats.opusOutputTokens(for: "2026-02-16"), 50000)
        XCTAssertEqual(stats.sonnetOutputTokens(for: "2026-02-16"), 10000)
        // effectiveTokens = 1000 + 5000 + 2000 + 100000/10 = 18000
        XCTAssertEqual(stats.totalOpusEffectiveTokens, 18000)
    }
}
