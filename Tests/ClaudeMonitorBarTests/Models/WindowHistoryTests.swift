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

    // MARK: - migrateIfNeeded

    func testMigrationBucketsSnapshotsByWindowAndKeepsMax() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)  // current 5h window end
        let w = 5.0 * 3600
        let snapshots = [
            // previous window (ends at anchor - 5h)
            UsageSnapshot(timestamp: anchor - w - 3600, fiveHourUtil: 0.30, sevenDayUtil: 0.50),
            UsageSnapshot(timestamp: anchor - w - 600,  fiveHourUtil: 0.65, sevenDayUtil: 0.52),
            // current window
            UsageSnapshot(timestamp: anchor - 1800,     fiveHourUtil: 0.12, sevenDayUtil: 0.55),
        ]

        store.migrateIfNeeded(snapshots: snapshots, fiveHourReset: anchor, sevenDayReset: nil)

        let five = store.load().filter { $0.kind == .fiveHour }
        XCTAssertEqual(five.count, 2)
        XCTAssertEqual(five[0].end, anchor - w)
        XCTAssertEqual(five[0].peak, 0.65, accuracy: 0.0001)
        XCTAssertEqual(five[1].end, anchor)
        XCTAssertEqual(five[1].peak, 0.12, accuracy: 0.0001)
    }

    func testMigrationHandlesBothKinds() {
        let fiveAnchor = Date(timeIntervalSince1970: 1_800_000_000)
        let sevenAnchor = fiveAnchor.addingTimeInterval(3 * 86400)
        let snapshots = [
            UsageSnapshot(timestamp: fiveAnchor - 600, fiveHourUtil: 0.40, sevenDayUtil: 0.60)
        ]

        store.migrateIfNeeded(
            snapshots: snapshots,
            fiveHourReset: fiveAnchor,
            sevenDayReset: sevenAnchor
        )

        let windows = store.load()
        XCTAssertEqual(windows.filter { $0.kind == .fiveHour }.count, 1)
        XCTAssertEqual(windows.filter { $0.kind == .sevenDay }.count, 1)
        XCTAssertEqual(windows.first { $0.kind == .sevenDay }?.peak ?? 0, 0.60, accuracy: 0.0001)
    }

    func testMigrationIsSkippedOnceStoreExists() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        store.record(kind: .fiveHour, end: anchor, value: 0.05)

        store.migrateIfNeeded(
            snapshots: [UsageSnapshot(timestamp: anchor - 600, fiveHourUtil: 0.99, sevenDayUtil: 0.99)],
            fiveHourReset: anchor,
            sevenDayReset: anchor
        )

        let windows = store.load()
        XCTAssertEqual(windows.count, 1, "an existing store must not be overwritten")
        XCTAssertEqual(windows[0].peak, 0.05, accuracy: 0.0001)
    }

    func testMigrationIgnoresSnapshotsNewerThanTheAnchor() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshots = [
            UsageSnapshot(timestamp: anchor + 3600, fiveHourUtil: 0.90, sevenDayUtil: 0.90),
            UsageSnapshot(timestamp: anchor - 600,  fiveHourUtil: 0.25, sevenDayUtil: 0.25),
        ]

        store.migrateIfNeeded(snapshots: snapshots, fiveHourReset: anchor, sevenDayReset: nil)

        let five = store.load().filter { $0.kind == .fiveHour }
        XCTAssertEqual(five.count, 1)
        XCTAssertEqual(five[0].peak, 0.25, accuracy: 0.0001)
    }

    func testMigrationWithNoSnapshotsWritesNothing() {
        store.migrateIfNeeded(snapshots: [], fiveHourReset: Date(), sevenDayReset: Date())
        XCTAssertTrue(store.load().isEmpty)
    }
}
