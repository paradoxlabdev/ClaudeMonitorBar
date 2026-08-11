# Persisted usage windows + horizontally scrollable charts — design

Date: 2026-08-11
Status: approved by user ("pasuje, rób")

## Context

The popover charts show at most 5 five-hour windows and 4 seven-day windows. Both counts are
hardcoded as `for i in (0..<5)` / `(0..<4)` loops in `UsageChartView`, so no amount of stored
history widens them. The user wants the bars persisted and both charts scrollable sideways to
reach everything on disk.

Two independent defects surfaced while reading the current code:

- **Bars are derived, not stored.** `UsageChartView` recomputes windows on every render by
  filtering the raw snapshot array against window boundaries walked backwards from the API
  reset timestamp. Raw snapshots are trimmed to 30 days, so history beyond that is gone even
  though the derived bars would be tiny.
- **Each window takes the *last* snapshot in range, not the highest.** If the app was asleep at
  reset time, the bar reports a mid-window value and understates the window.

Windows are also aligned by walking `reset − k × windowSeconds` backwards. Reset timestamps
drift (notably the 7-day reset, anchored to the subscription), so derived boundaries diverge
further the deeper into history you look.

## Decisions taken with the user

- Retention: **unlimited**. One record per completed window, ~50 B; a year of 5-hour windows is
  ~90 KB.
- Windows with no measurement (app closed, Mac asleep) render as **an empty gap** — no bar —
  not a zero bar. A zero bar cannot be told apart from genuine zero usage.
- **8 windows visible** at a time in the scroll viewport; the rest reachable by scrolling.

## Storage — `Models/WindowHistory.swift`

```swift
enum WindowKind: String, Codable { case fiveHour, sevenDay }

struct UsageWindow: Codable, Identifiable {
    let kind: WindowKind
    let end: Date        // reset timestamp observed from the API — the window's end
    let peak: Double     // highest utilization observed inside the window
}
```

Persisted to `windows.json` in the existing
`~/Library/Application Support/ClaudeMonitorBar/` directory. Never trimmed.

`record(kind:end:value:)` upserts on every fetch: take the newest stored record of that kind;
if `abs(end - stored.end) < windowSeconds / 2`, it is the **same window** — set
`peak = max(peak, value)` and adopt the later `end`. Otherwise append a new record.

Two choices worth stating:

- **`peak` rather than the last reading.** Utilization only grows inside a window, so the peak
  equals the value at reset — but it survives the app being closed at that moment. This is what
  fixes the understating defect above.
- **Store the `end` observed from the API rather than computing `reset − k × windowSeconds`.**
  The half-window tolerance absorbs reset drift without mistaking it for a new window, and
  stored boundaries cannot accumulate error over time.

`load() -> [UsageWindow]` returns records sorted ascending by `end`.

Storage path is injectable (`init(storageURL:)` plus a `shared` instance) so tests can point at
a temp directory, matching the pattern already used by `LocalUsageScanner`.

**Migration.** On first launch with no `windows.json`, backfill from the existing
`history.json`: group raw snapshots into windows and take the max per window. Users with
accumulated history keep it. After migration the app stops writing raw snapshots — `windows.json`
becomes the single source of truth. The old `history.json` is left on disk untouched.

## Charts — `Views/UsageChartView.swift`

The X axis changes from `String` (a formatted label) to `Date` (the window end). That one change
unlocks the rest:

- `.chartScrollableAxes(.horizontal)` with `.chartXVisibleDomain(length: 8 × windowSeconds)`
  puts 8 windows in frame and the remainder past the edge.
- `.chartScrollPosition(initialX:)` pins the opening view to the right edge — the popover opens
  on now, and scrolling left walks into the past.
- **Gaps come for free.** A window with no record produces no `BarMark`, leaving empty space on
  the time axis. With a categorical axis the gap would have to be faked with placeholder entries.
- X labels: an explicit list of every second window end (`HH:mm` for 5-hour, `MMM d` for 7-day),
  so 8 bars' worth of labels do not collide.

Bar colors (green < 70%, yellow < 90%, red ≥ 90%) and the 60 pt chart height are unchanged.

Each section header gains a count of stored windows — `5-Hour Windows · 37` — otherwise there is
no indication that anything lies beyond the viewport.

The in-progress window keeps receiving its live value from `usageLimits`, overlaid on the stored
record as `max(stored, live)`. The bar then reacts immediately rather than waiting for a write,
and debug mode's mock values still drive the chart.

`SessionManager.usageHistory: [UsageSnapshot]` becomes `usageWindows: [UsageWindow]`; it has no
consumer other than this chart.

## Error handling

- Unreadable or corrupt `windows.json`: treated as empty, same as the current loader. The next
  successful fetch rewrites it.
- Missing reset timestamp from the API: the window cannot be keyed, so nothing is recorded for
  that fetch.
- Empty history: the chart section stays hidden, as it does today.

## Testing

`Tests/ClaudeMonitorBarTests/Models/WindowHistoryTests.swift`, XCTest against a temp-directory
store:

- upsert keeps the maximum within one window
- a new window end appends a new record
- reset drift below half a window updates the existing record rather than appending
- migration from raw snapshots groups by window and takes the max
- a record a year old survives (no retention cutoff)
- `load()` returns records sorted ascending

Scrolling, label density, and gap rendering verified manually against an injected fixture store,
since real data accrues at one 5-hour window per 5 hours.

## Out of scope

Click-to-inspect tooltips with exact values, zoom, CSV export, widening the 300 pt popover.
