import XCTest
@testable import ClaudeMonitorBar

final class HistoryParserTests: XCTestCase {
    func testParseHistoryLine() throws {
        let json = """
        {"display":"test","pastedContents":{},"timestamp":1770958765835,"project":"/Users/test/myproject","sessionId":"abc-123"}
        """
        let entry = try HistoryParser.parseLine(json)
        XCTAssertEqual(entry.project, "/Users/test/myproject")
        XCTAssertEqual(entry.sessionId, "abc-123")
    }

    func testProjectForSession() {
        let entries = [
            HistoryParser.HistoryEntry(project: "/Users/test/projectA", sessionId: "s1", timestamp: 100),
            HistoryParser.HistoryEntry(project: "/Users/test/projectB", sessionId: "s2", timestamp: 200),
        ]
        XCTAssertEqual(HistoryParser.projectPath(forSession: "s2", in: entries), "/Users/test/projectB")
    }
}
