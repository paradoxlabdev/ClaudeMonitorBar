import XCTest
@testable import ClaudeMonitorBar

final class ClaudeSessionTests: XCTestCase {
    func testSessionIsActive() {
        let session = ClaudeSession(
            pid: 1234,
            projectPath: "/Users/test/project",
            sessionId: "abc-123",
            tokenCount: 5000,
            startTime: Date()
        )
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.projectName, "project")
    }

    func testSessionCostCalculation() {
        let session = ClaudeSession(
            pid: 1234,
            projectPath: "/Users/test/project",
            sessionId: "abc-123",
            tokenCount: 100_000,
            startTime: Date()
        )
        // 100k tokens at Opus input rate ($15/1M) = $1.50
        let cost = session.estimatedCost(inputRate: 15.0, outputRate: 75.0)
        XCTAssertEqual(cost, 1.50, accuracy: 0.01)
    }
}
