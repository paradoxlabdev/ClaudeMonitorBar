# Persisted Usage Windows + Scrollable Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist each completed 5-hour and 7-day usage window as its own record kept forever, and make both popover charts scroll horizontally through that entire history.

**Architecture:** A new `WindowHistory` store writes one `UsageWindow` row per window to `windows.json`, upserting the in-progress window by maximum on every fetch. `UsageChartView` switches its X axis from a formatted `String` to the window-end `Date`, which enables SwiftUI Charts' native horizontal scrolling and makes missing windows render as real gaps. `SessionManager` feeds the store and exposes `usageWindows` instead of raw snapshots.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Charts, XCTest, SwiftPM (`swift build` / `swift test`), macOS 14 deployment target.

## Global Constraints

- Deployment target is **macOS 14** (`Package.swift` → `platforms: [.macOS(.v14)]`). `chartScrollableAxes`, `chartXVisibleDomain`, and `chartScrollPosition` are all macOS 14.0+ — do not raise the target.
- Window records are **never trimmed**. Do not add a retention cutoff anywhere.
- Windows with no measurement must render as **empty space** — never a zero-height or placeholder bar.
- **8 windows visible** in the scroll viewport (`visibleWindows = 8`).
- `RateLimitData.fiveHourReset` and `.sevenDayReset` are non-optional `Int` but are **`0` when the header is absent** (`RateLimitFetcher.swift:140` returns `?? 0`, and `RateLimitFetcher.swift:186-187` hardcodes `0` on a 429 without headers). Treat `<= 0` as "no reset known" everywhere and skip recording.
- Existing popover width is 300 pt and chart height 60 pt. Both stay as they are.
- Bar colors stay: `>= 0.9` red, `>= 0.7` yellow, else green.
- Tests use XCTest with a temp directory, matching `Tests/ClaudeMonitorBarTests/Services/LocalUsageScannerTests.swift`.
- Path injection follows `LocalUsageScanner`'s pattern: `init(storageURL: URL? = nil)` alongside a `static let shared`.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/ClaudeMonitorBar/Models/WindowHistory.swift` (create) | `WindowKind`, `UsageWindow`, and the `WindowHistory` store: load, upsert-by-max, one-time migration. No UI, no networking. |
| `Sources/ClaudeMonitorBar/Models/UsageHistory.swift` (modify) | Demoted to a legacy read-only loader for `history.json`, used solely as the migration source. `append` and the 30-day trim are removed. |
| `Sources/ClaudeMonitorBar/Services/SessionManager.swift` (modify) | Records windows after each successful fetch; publishes `usageWindows`. |
| `Sources/ClaudeMonitorBar/Views/UsageChartView.swift` (rewrite) | Date-axis scrollable charts driven by `[UsageWindow]`, with the live value overlaid on the in-progress window. |
| `Sources/ClaudeMonitorBar/Views/MenuBarView.swift` (modify) | Passes `usageWindows` and gates the section on it. |
| `Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift` (create) | Unit tests for the store against a temp-directory file. |

Task order: **1 → 2 → 3 → 4**. Task 1 is pure model + tests, Task 2 is migration + tests, Task 3 wires the manager, Task 4 rewrites the view.

---

### Task 1: `WindowHistory` store with upsert-by-max

**Files:**
- Create: `Sources/ClaudeMonitorBar/Models/WindowHistory.swift`
- Test: `Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum WindowKind: String, Codable { case fiveHour, sevenDay }` with `var seconds: TimeInterval`
  - `struct UsageWindow: Codable, Identifiable, Equatable { let kind: WindowKind; let end: Date; let peak: Double }`
  - `final class WindowHistory` with `static let shared`, `init(storageURL: URL? = nil)`, `func load() -> [UsageWindow]`, `func record(kind: WindowKind, end: Date, value: Double)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WindowHistoryTests`
Expected: FAIL — compile error, `cannot find 'WindowHistory' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ClaudeMonitorBar/Models/WindowHistory.swift`:

```swift
import Foundation

enum WindowKind: String, Codable {
    case fiveHour
    case sevenDay

    /// Nominal window length. Half of this is the tolerance that decides whether an
    /// observed reset belongs to the newest stored window or opens a new one.
    var seconds: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .sevenDay: return 7 * 86400
        }
    }
}

struct UsageWindow: Codable, Identifiable, Equatable {
    let kind: WindowKind
    let end: Date       // reset timestamp as observed from the API — the window's end
    let peak: Double    // highest utilization seen inside the window, 0...1

    var id: String { "\(kind.rawValue)-\(end.timeIntervalSince1970)" }
}

/// Persistent record of usage windows — one row per window, kept forever.
///
/// Bars used to be derived on the fly from raw snapshots trimmed at 30 days, which
/// capped how far back the charts could reach and made every bar depend on a snapshot
/// happening to land near the reset. Storing the window itself makes history unbounded
/// (~50 B per row) and keeps the peak, which is what the window was worth at reset.
final class WindowHistory {
    static let shared = WindowHistory()

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultDirectory().appendingPathComponent("windows.json")
    }

    private static func defaultDirectory() -> URL {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory
        }
        let dir = support.appendingPathComponent("ClaudeMonitorBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() -> [UsageWindow] {
        guard let data = try? Data(contentsOf: storageURL),
              let windows = try? JSONDecoder().decode([UsageWindow].self, from: data) else {
            return []
        }
        return windows.sorted { $0.end < $1.end }
    }

    /// Upsert the window ending at `end`.
    ///
    /// Utilization only grows inside a window, so keeping the max both matches the value
    /// at reset and survives the app being closed at that moment. Reset timestamps drift
    /// by minutes, so anything within half a window is the same window, not a new one.
    func record(kind: WindowKind, end: Date, value: Double) {
        var windows = load()

        if let idx = windows.lastIndex(where: { $0.kind == kind }),
           abs(windows[idx].end.timeIntervalSince(end)) < kind.seconds / 2 {
            windows[idx] = UsageWindow(kind: kind, end: end, peak: max(windows[idx].peak, value))
        } else {
            windows.append(UsageWindow(kind: kind, end: end, peak: value))
        }

        save(windows)
    }

    private func save(_ windows: [UsageWindow]) {
        let sorted = windows.sorted { $0.end < $1.end }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
```

Note: `load()` sorts ascending, so `lastIndex(where: { $0.kind == kind })` is the newest record of that kind.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WindowHistoryTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeMonitorBar/Models/WindowHistory.swift Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift
git commit -m "feat: persistent per-window usage history store"
```

---

### Task 2: One-time migration from raw snapshots

**Files:**
- Modify: `Sources/ClaudeMonitorBar/Models/WindowHistory.swift` (add `migrateIfNeeded`)
- Test: `Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift` (add cases)

This task is purely additive, so it builds and commits on its own. Slimming `UsageHistory` down to a reader belongs to Task 3, where the caller that would break is fixed in the same change.

**Interfaces:**
- Consumes: `UsageWindow`, `WindowKind`, `WindowHistory.load/record/save` from Task 1; `UsageSnapshot` from the existing `UsageHistory.swift`.
- Produces: `func migrateIfNeeded(snapshots: [UsageSnapshot], fiveHourReset: Date?, sevenDayReset: Date?)` — a no-op once `windows.json` exists.

**Bucketing math.** A window ending at `E` covers `(E - W, E]`. Given the current window end `A` (the live reset) and a snapshot at `t <= A`, the snapshot's window index back from `A` is `k = floor((A - t) / W)` and its window end is `A - k * W`. The upper bound is inclusive, which is exactly what `floor` gives when `A - t` is an exact multiple of `W`.

- [ ] **Step 1: Write the failing tests**

Append inside `WindowHistoryTests`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WindowHistoryTests`
Expected: FAIL — `value of type 'WindowHistory' has no member 'migrateIfNeeded'`.

- [ ] **Step 3: Write the implementation**

Add to `WindowHistory` in `Sources/ClaudeMonitorBar/Models/WindowHistory.swift`:

```swift
    /// One-time backfill from the legacy raw-snapshot file so users upgrading do not
    /// lose their existing history. No-op once `windows.json` exists.
    ///
    /// Snapshots carry no window boundaries, so they are bucketed backwards from the
    /// live reset: a window ending at `E` covers `(E - W, E]`, therefore a snapshot at
    /// `t` belongs to the window `floor((anchor - t) / W)` steps back from the anchor.
    func migrateIfNeeded(snapshots: [UsageSnapshot], fiveHourReset: Date?, sevenDayReset: Date?) {
        guard !FileManager.default.fileExists(atPath: storageURL.path) else { return }
        guard !snapshots.isEmpty else { return }

        var windows: [UsageWindow] = []
        if let anchor = fiveHourReset {
            windows += Self.bucket(snapshots, kind: .fiveHour, anchor: anchor) { $0.fiveHourUtil }
        }
        if let anchor = sevenDayReset {
            windows += Self.bucket(snapshots, kind: .sevenDay, anchor: anchor) { $0.sevenDayUtil }
        }

        guard !windows.isEmpty else { return }
        save(windows)
    }

    private static func bucket(
        _ snapshots: [UsageSnapshot],
        kind: WindowKind,
        anchor: Date,
        value: (UsageSnapshot) -> Double
    ) -> [UsageWindow] {
        var peaks: [TimeInterval: Double] = [:]

        for snapshot in snapshots {
            let delta = anchor.timeIntervalSince(snapshot.timestamp)
            guard delta >= 0 else { continue }  // snapshot ahead of the reset — unusable
            let stepsBack = (delta / kind.seconds).rounded(.down)
            let end = anchor.timeIntervalSince1970 - stepsBack * kind.seconds
            peaks[end] = max(peaks[end] ?? 0, value(snapshot))
        }

        return peaks
            .map { UsageWindow(kind: kind, end: Date(timeIntervalSince1970: $0.key), peak: $0.value) }
            .sorted { $0.end < $1.end }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WindowHistoryTests`
Expected: PASS, 13 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeMonitorBar/Models/WindowHistory.swift Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift
git commit -m "feat: migrate legacy usage snapshots into window records"
```

---

### Task 3: Wire `SessionManager` to the window store

**Files:**
- Modify: `Sources/ClaudeMonitorBar/Services/SessionManager.swift:20` (property), `:61` (startup load), `:157-164` (record block)
- Modify: `Sources/ClaudeMonitorBar/Models/UsageHistory.swift:11,30-48` (delete `maxDays` and `append`)
- Test: `Tests/ClaudeMonitorBarTests/Services/SessionManagerTests.swift`

**Interfaces:**
- Consumes: `WindowHistory.shared.load()`, `.record(kind:end:value:)`, `.migrateIfNeeded(snapshots:fiveHourReset:sevenDayReset:)`, `UsageWindow`, `WindowKind` from Tasks 1–2.
- Produces: `SessionManager.usageWindows: [UsageWindow]`, replacing `usageHistory: [UsageSnapshot]`.

- [ ] **Step 1: Write the failing test**

Replace the body of `Tests/ClaudeMonitorBarTests/Services/SessionManagerTests.swift`:

```swift
import XCTest
@testable import ClaudeMonitorBar

final class SessionManagerTests: XCTestCase {
    func testSessionManagerStartsEmpty() {
        let manager = SessionManager()
        XCTAssertTrue(manager.usageLimits.isEmpty)
        XCTAssertEqual(manager.overallPercentage, 0)
        XCTAssertTrue(manager.usageWindows.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionManagerTests`
Expected: FAIL — `value of type 'SessionManager' has no member 'usageWindows'`.

- [ ] **Step 3: Write the implementation**

In `Sources/ClaudeMonitorBar/Services/SessionManager.swift`, replace line 20:

```swift
    var usageWindows: [UsageWindow] = []
```

Replace line 61 inside `startMonitoring()`:

```swift
        usageWindows = WindowHistory.shared.load()
```

Replace the "Save to history" block (lines 157-164) with:

```swift
                    // Record the in-progress windows. A reset of 0 means the header was
                    // absent (see RateLimitFetcher's 429-without-headers path) — that is
                    // not a real window boundary, so skip it rather than stamping 1970.
                    let fiveEnd = data.fiveHourReset > 0
                        ? Date(timeIntervalSince1970: Double(data.fiveHourReset)) : nil
                    let sevenEnd = data.sevenDayReset > 0
                        ? Date(timeIntervalSince1970: Double(data.sevenDayReset)) : nil

                    // Must run before the first record() call, which would create the file
                    // and make the migration a no-op.
                    WindowHistory.shared.migrateIfNeeded(
                        snapshots: UsageHistory.load(),
                        fiveHourReset: fiveEnd,
                        sevenDayReset: sevenEnd
                    )

                    if let fiveEnd {
                        WindowHistory.shared.record(
                            kind: .fiveHour, end: fiveEnd, value: data.fiveHourUtilization
                        )
                    }
                    if let sevenEnd {
                        WindowHistory.shared.record(
                            kind: .sevenDay, end: sevenEnd, value: data.sevenDayUtilization
                        )
                    }
                    self.usageWindows = WindowHistory.shared.load()
```

Then reduce `Sources/ClaudeMonitorBar/Models/UsageHistory.swift` to a legacy reader. Its only remaining caller is the migration above, so delete `maxDays` (line 11) and the entire `append` function (lines 30-48), leaving:

```swift
import Foundation

struct UsageSnapshot: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let fiveHourUtil: Double
    let sevenDayUtil: Double
}

/// Legacy raw-snapshot log. Superseded by `WindowHistory`, which stores one row per
/// window instead of one row per poll. Kept read-only as the migration source; the
/// file itself is left on disk untouched.
enum UsageHistory {
    static var storageURL: URL {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeMonitorBar-history.json")
        }
        let dir = support.appendingPathComponent("ClaudeMonitorBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static func load() -> [UsageSnapshot] {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshots = try? JSONDecoder().decode([UsageSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionManagerTests`
Expected: PASS. The full suite (`swift test`) will still fail to build until Task 4 updates `MenuBarView`, which references `sessionManager.usageHistory` at `MenuBarView.swift:123,129`.

- [ ] **Step 5: Commit**

Hold the commit until Task 4 compiles — Tasks 3 and 4 land together:

```bash
# no commit here; see Task 4 Step 6
```

---

### Task 4: Date-axis scrollable charts

**Files:**
- Rewrite: `Sources/ClaudeMonitorBar/Views/UsageChartView.swift`
- Modify: `Sources/ClaudeMonitorBar/Views/MenuBarView.swift:123,129`

**Interfaces:**
- Consumes: `UsageWindow`, `WindowKind` (Task 1), `SessionManager.usageWindows` (Task 3).
- Produces: `UsageChartView(windows:fiveHourReset:sevenDayReset:currentFiveHour:currentSevenDay:)` — the `history:` label is replaced by `windows:`; the reset and current parameters keep their existing types (`Int?`, `Double`).

- [ ] **Step 1: Replace the chart view**

Overwrite `Sources/ClaudeMonitorBar/Views/UsageChartView.swift`:

```swift
import SwiftUI
import Charts

struct UsageChartView: View {
    let windows: [UsageWindow]
    let fiveHourReset: Int?
    let sevenDayReset: Int?
    var currentFiveHour: Double = 0
    var currentSevenDay: Double = 0

    /// Windows in the scroll viewport at once. The rest is reachable by scrolling.
    private static let visibleWindows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(
                kind: .fiveHour,
                title: "5-Hour Windows",
                dot: .green,
                reset: fiveHourReset,
                live: currentFiveHour,
                dateFormat: "HH:mm"
            )
            section(
                kind: .sevenDay,
                title: "7-Day Windows",
                dot: .orange,
                reset: sevenDayReset,
                live: currentSevenDay,
                dateFormat: "MMM d"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func section(
        kind: WindowKind,
        title: String,
        dot: Color,
        reset: Int?,
        live: Double,
        dateFormat: String
    ) -> some View {
        let points = points(kind: kind, reset: reset, live: live)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                // Without a count there is no hint that anything lies past the viewport.
                Text("· \(points.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
            }
            chart(points: points, kind: kind, dateFormat: dateFormat)
        }
    }

    @ViewBuilder
    private func chart(points: [UsageWindow], kind: WindowKind, dateFormat: String) -> some View {
        let visibleLength = Double(Self.visibleWindows) * kind.seconds
        let lastEnd = points.last?.end ?? Date()
        let firstEnd = points.first?.end ?? lastEnd
        // Half a window of padding on each side keeps the edge bars from being clipped,
        // and the domain is never shorter than one viewport or the scroll math degenerates.
        let domainEnd = lastEnd.addingTimeInterval(kind.seconds / 2)
        let domainStart = min(firstEnd, lastEnd.addingTimeInterval(-visibleLength))
            .addingTimeInterval(-kind.seconds / 2)
        let scrollStart = max(domainStart, domainEnd.addingTimeInterval(-visibleLength))

        Chart(points) { point in
            BarMark(
                x: .value("Window", point.end),
                y: .value("Usage", point.peak * 100),
                width: .fixed(22)
            )
            .foregroundStyle(barColor(point.peak))
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: domainStart...domainEnd)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(initialX: scrollStart)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)%")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: labelDates(points)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.formatted(date, dateFormat))
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
        .frame(height: 60)
    }

    /// Stored windows for `kind`, with the live reading folded into the in-progress
    /// window. Keeps the bar reacting immediately instead of waiting for a write, and
    /// keeps debug mode's mock values on the chart when nothing is stored yet.
    private func points(kind: WindowKind, reset: Int?, live: Double) -> [UsageWindow] {
        var result = windows.filter { $0.kind == kind }
        guard let reset, reset > 0 else { return result }

        let end = Date(timeIntervalSince1970: Double(reset))
        if let idx = result.lastIndex(where: {
            abs($0.end.timeIntervalSince(end)) < kind.seconds / 2
        }) {
            result[idx] = UsageWindow(kind: kind, end: end, peak: max(result[idx].peak, live))
        } else {
            result.append(UsageWindow(kind: kind, end: end, peak: live))
        }
        return result
    }

    /// Every second window end, anchored on the newest so the current window is labelled.
    /// Labelling all 8 visible bars makes "HH:mm" strings collide at 7 pt.
    private func labelDates(_ points: [UsageWindow]) -> [Date] {
        guard !points.isEmpty else { return [] }
        return Array(
            stride(from: points.count - 1, through: 0, by: -2)
                .map { points[$0].end }
                .reversed()
        )
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func barColor(_ value: Double) -> Color {
        if value >= 0.9 { return .red }
        if value >= 0.7 { return .yellow }
        return .green
    }
}
```

- [ ] **Step 2: Update the call site**

In `Sources/ClaudeMonitorBar/Views/MenuBarView.swift`, change line 123 from `if !sessionManager.usageHistory.isEmpty {` to:

```swift
                if !sessionManager.usageWindows.isEmpty {
```

and line 129 from `history: sessionManager.usageHistory,` to:

```swift
                        windows: sessionManager.usageWindows,
```

Leave the remaining four arguments unchanged.

- [ ] **Step 3: Build and run the full suite**

Run: `swift build 2>&1 | tail -20 && swift test`
Expected: build succeeds; every test passes — `WindowHistoryTests` 13, `SessionManagerTests` 1, and `LocalUsageScannerTests` unchanged from its pre-existing count.

- [ ] **Step 4: Verify scrolling against a seeded store**

Real data accrues at one 5-hour window per 5 hours, so seed a fixture before launching. Back up the live store first, then write 20 five-hour and 10 seven-day windows:

```bash
cd ~/Library/Application\ Support/ClaudeMonitorBar
cp windows.json windows.json.bak 2>/dev/null || true
python3 - <<'PY'
import json, os, time
now = time.time()
rows = []
for i in range(20):
    rows.append({"kind": "fiveHour",
                 "end": (now - i * 5 * 3600) - 978307200,
                 "peak": [0.12, 0.45, 0.78, 0.95, 0.0][i % 5]})
for i in range(10):
    rows.append({"kind": "sevenDay",
                 "end": (now - i * 7 * 86400) - 978307200,
                 "peak": [0.30, 0.62, 0.88][i % 3]})
rows.sort(key=lambda r: r["end"])
p = os.path.expanduser("~/Library/Application Support/ClaudeMonitorBar/windows.json")
json.dump(rows, open(p, "w"))
print("seeded", len(rows), "windows")
PY
```

`JSONEncoder` writes `Date` as seconds since the 2001 reference date, hence the `- 978307200`.

Then: `./build-app.sh && open ClaudeMonitorBar.app`, open the popover and confirm:
- both charts show 8 bars and scroll left with a two-finger trackpad swipe
- they open pinned to the right (newest window at the edge)
- headers read `5-Hour Windows · 20` and `7-Day Windows · 10`
- X labels appear on every second bar and do not overlap
- deleting a few middle rows from the seed leaves visible empty gaps, not zero bars

Restore afterwards: `mv windows.json.bak windows.json` (or delete the seed to start clean).

- [ ] **Step 5: Update the README chart description if it mentions fixed window counts**

Run: `grep -n "5 windows\|last 5\|last 4\|window" README.md` — if any line states a fixed number of chart bars, reword it to describe the scrollable full history. If nothing matches, skip.

- [ ] **Step 6: Commit Tasks 3 and 4 together**

```bash
git add Sources/ClaudeMonitorBar/Services/SessionManager.swift \
        Sources/ClaudeMonitorBar/Models/UsageHistory.swift \
        Sources/ClaudeMonitorBar/Views/UsageChartView.swift \
        Sources/ClaudeMonitorBar/Views/MenuBarView.swift \
        Tests/ClaudeMonitorBarTests/Services/SessionManagerTests.swift \
        README.md
git commit -m "feat: scrollable 5h/7d charts over full window history"
```

---

## Risks

- **`chartScrollPosition(initialX:)` sets the leading edge of the visible domain.** If the charts open showing the oldest data instead of the newest, the `scrollStart` computation is wrong, not the approach — it must be `domainEnd - visibleLength`, clamped to `domainStart`.
- **Scrolling inside an `NSPopover`.** Two-finger trackpad scroll is expected to work since nothing else in the popover scrolls, but this is the one behaviour that cannot be unit-tested. If gestures are swallowed, the fallback is a pair of chevron buttons stepping `chartScrollPosition` by one window; raise it before implementing rather than silently changing the design.
- **`.fixed(22)` bar width** assumes ~246 pt of plot area over 8 slots (~30 pt each). If bars look cramped or overlap, adjust the constant — do not change `visibleWindows`, which the user chose explicitly.
