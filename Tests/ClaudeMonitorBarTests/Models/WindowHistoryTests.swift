import XCTest
@testable import ClaudeMonitorBar

final class WindowHistoryTests: XCTestCase {
    private var tempDir: URL!
    private var store: WindowHistory!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = WindowHistory(storageURL: tempDir.appendingPathComponent("windows.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - record

    func testRecordKeepsMaximumWithinOneWindow() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        store.record(kind: .fiveHour, end: end, value: 0.20)
        store.record(kind: .fiveHour, end: end, value: 0.55)
        store.record(kind: .fiveHour, end: end, value: 0.40)

        let windows = store.load()
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].peak, 0.55, accuracy: 0.0001)
        XCTAssertEqual(windows[0].kind, .fiveHour)
    }

    func testNewWindowEndAppendsRecord() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = first.addingTimeInterval(5 * 3600)
        store.record(kind: .fiveHour, end: first, value: 0.80)
        store.record(kind: .fiveHour, end: second, value: 0.10)

        let windows = store.load()
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].peak, 0.80, accuracy: 0.0001)
        XCTAssertEqual(windows[1].peak, 0.10, accuracy: 0.0001)
    }

    func testResetDriftBelowHalfWindowUpdatesExistingRecord() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        store.record(kind: .fiveHour, end: end, value: 0.30)
        // API reset drifted 4 minutes later — same window, not a new one.
        let drifted = end.addingTimeInterval(240)
        store.record(kind: .fiveHour, end: drifted, value: 0.35)

        let windows = store.load()
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].end, drifted, "the newer observed reset wins")
        XCTAssertEqual(windows[0].peak, 0.35, accuracy: 0.0001)
    }

    func testKindsAreTrackedIndependently() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        store.record(kind: .fiveHour, end: end, value: 0.30)
        store.record(kind: .sevenDay, end: end, value: 0.70)

        let windows = store.load()
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.filter { $0.kind == .fiveHour }.count, 1)
        XCTAssertEqual(windows.filter { $0.kind == .sevenDay }.count, 1)
    }

    func testOldRecordsAreNeverTrimmed() {
        let old = Date().addingTimeInterval(-400 * 86400)
        store.record(kind: .fiveHour, end: old, value: 0.42)
        store.record(kind: .fiveHour, end: Date(), value: 0.11)

        let windows = store.load()
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].peak, 0.42, accuracy: 0.0001)
    }

    // MARK: - load

    func testLoadReturnsRecordsSortedByEndAscending() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        store.record(kind: .fiveHour, end: base.addingTimeInterval(10 * 3600), value: 0.10)
        store.record(kind: .fiveHour, end: base, value: 0.20)

        let ends = store.load().map(\.end)
        XCTAssertEqual(ends, ends.sorted())
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertTrue(store.load().isEmpty)
    }

    func testCorruptFileLoadsEmpty() throws {
        try "not json".write(
            to: tempDir.appendingPathComponent("windows.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(store.load().isEmpty)
    }
}
