import XCTest
@testable import ClaudeMonitorBar

final class SessionManagerTests: XCTestCase {
    func testSessionManagerStartsEmpty() {
        let manager = SessionManager()
        XCTAssertTrue(manager.usageLimits.isEmpty)
        XCTAssertEqual(manager.overallPercentage, 0)
    }
}
