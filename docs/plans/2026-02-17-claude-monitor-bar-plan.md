# Claude Monitor Bar — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar app that monitors active Claude Code sessions and displays token usage / estimated costs.

**Architecture:** SwiftUI MenuBarExtra app with no dock icon. Polls running `claude` processes every 5s, watches `~/.claude/debug/*.txt` for token data via FSEvents. Persists daily/monthly stats in a local JSON file.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+ (Sonoma), AppKit (NSWorkspace), FSEvents

---

## Data Sources (discovered from `~/.claude/`)

| Source | Path | Content |
|--------|------|---------|
| Stats cache | `~/.claude/stats-cache.json` | Daily message/session/tool counts |
| Debug logs | `~/.claude/debug/<session-id>.txt` | Token counts (`tokens=38125`), status lines (`↑ 2.0k tokens`) |
| History | `~/.claude/history.jsonl` | Commands with project path, sessionId, timestamp |
| Processes | `pgrep -fl claude` | Running claude PIDs with env vars |

---

### Task 1: Create Xcode Project Skeleton

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar.xcodeproj` (via xcodebuild)
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/ClaudeMonitorBarApp.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Info.plist`

**Step 1: Generate Swift Package / Xcode project**

Create the project using `swift package init` and then convert to an app, or create files manually.

```swift
// ClaudeMonitorBarApp.swift
import SwiftUI

@main
struct ClaudeMonitorBarApp: App {
    var body: some Scene {
        MenuBarExtra("Claude Monitor", systemImage: "circle.fill") {
            Text("Claude Monitor Bar")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

**Step 2: Configure Info.plist for menu-bar-only app**

Set `LSUIElement = true` to hide from Dock.

**Step 3: Build and run to verify menu bar icon appears**

Run: `xcodebuild -scheme ClaudeMonitorBar build`
Expected: App compiles, icon appears in menu bar.

**Step 4: Commit**

```bash
git init
git add .
git commit -m "feat: initial Xcode project with MenuBarExtra skeleton"
```

---

### Task 2: Data Models

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Models/ClaudeSession.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Models/DailyStats.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBarTests/Models/ClaudeSessionTests.swift`

**Step 1: Write the failing test**

```swift
// ClaudeSessionTests.swift
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
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeMonitorBar -destination 'platform=macOS'`
Expected: FAIL — `ClaudeSession` not defined.

**Step 3: Write minimal implementation**

```swift
// ClaudeSession.swift
import Foundation

struct ClaudeSession: Identifiable {
    let id: String  // sessionId
    let pid: Int32
    let projectPath: String
    let sessionId: String
    var tokenCount: Int
    let startTime: Date
    var lastUpdated: Date = Date()

    var isActive: Bool { true }

    var projectName: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    func estimatedCost(inputRate: Double, outputRate: Double) -> Double {
        // Simplified: treat all tokens as input for now
        return Double(tokenCount) / 1_000_000.0 * inputRate
    }

    init(pid: Int32, projectPath: String, sessionId: String, tokenCount: Int, startTime: Date) {
        self.pid = pid
        self.projectPath = projectPath
        self.sessionId = sessionId
        self.tokenCount = tokenCount
        self.startTime = startTime
        self.id = sessionId
    }
}
```

```swift
// DailyStats.swift
import Foundation

struct DailyStats: Codable {
    let date: String  // "YYYY-MM-DD"
    var messageCount: Int
    var sessionCount: Int
    var toolCallCount: Int
    var estimatedTokens: Int
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme ClaudeMonitorBar -destination 'platform=macOS'`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add ClaudeSession and DailyStats data models with tests"
```

---

### Task 3: Process Monitor — Detect Running Claude Sessions

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Services/ProcessMonitor.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBarTests/Services/ProcessMonitorTests.swift`

**Step 1: Write the failing test**

```swift
// ProcessMonitorTests.swift
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
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `ProcessMonitor` not defined.

**Step 3: Write minimal implementation**

```swift
// ProcessMonitor.swift
import Foundation

@Observable
class ProcessMonitor {
    var runningPIDs: [Int32] = []
    private var timer: Timer?

    struct ProcessInfo {
        let pid: Int32
    }

    static func parseProcessLine(_ line: String) -> ProcessInfo? {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard let first = parts.first, let pid = Int32(first) else { return nil }
        return ProcessInfo(pid: pid)
    }

    func startMonitoring(interval: TimeInterval = 5.0) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "claude"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").map(String.init)

            runningPIDs = lines.compactMap { Self.parseProcessLine($0)?.pid }
        } catch {
            runningPIDs = []
        }
    }
}
```

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add ProcessMonitor to detect running claude processes"
```

---

### Task 4: Debug Log Parser — Extract Token Counts

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Services/DebugLogParser.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBarTests/Services/DebugLogParserTests.swift`

**Step 1: Write the failing test**

```swift
// DebugLogParserTests.swift
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
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

```swift
// DebugLogParser.swift
import Foundation

enum DebugLogParser {
    /// Extract token count from "autocompact: tokens=38125"
    static func extractTokenCount(from line: String) -> Int? {
        guard let range = line.range(of: #"tokens=(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let match = line[range]
        let numStr = match.split(separator: "=").last.map(String.init) ?? ""
        return Int(numStr)
    }

    /// Extract token count from status line "↑ 2.0k tokens"
    static func extractTokenCountFromStatus(_ line: String) -> Int? {
        guard let range = line.range(of: #"↑\s*([\d.]+)k?\s*tokens"#, options: .regularExpression) else {
            return nil
        }
        let snippet = String(line[range])
        // Extract the number after ↑
        let cleaned = snippet
            .replacingOccurrences(of: "↑", with: "")
            .replacingOccurrences(of: "tokens", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleaned.hasSuffix("k") {
            let numStr = String(cleaned.dropLast())
            guard let num = Double(numStr) else { return nil }
            return Int(num * 1000)
        }
        guard let num = Double(cleaned) else { return nil }
        return Int(num)
    }

    /// Get the latest token count from a debug log file
    static func latestTokenCount(from fileURL: URL) -> Int? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            if let tokens = extractTokenCount(from: line) {
                return tokens
            }
        }
        return nil
    }

    /// Extract session ID from debug log filename
    static func sessionId(from filename: String) -> String {
        return filename.replacingOccurrences(of: ".txt", with: "")
    }
}
```

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add DebugLogParser to extract token counts from Claude debug logs"
```

---

### Task 5: Stats Cache Reader

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Services/StatsCacheReader.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBarTests/Services/StatsCacheReaderTests.swift`

**Step 1: Write the failing test**

```swift
// StatsCacheReaderTests.swift
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
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let stats = try StatsCacheReader.parse(data: data)
        XCTAssertEqual(stats.dailyActivity.count, 1)
        XCTAssertEqual(stats.dailyActivity[0].messageCount, 100)
        XCTAssertEqual(stats.todayStats?.messageCount, 100)
    }
}
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

```swift
// StatsCacheReader.swift
import Foundation

struct StatsCache: Codable {
    let version: Int
    let lastComputedDate: String
    let dailyActivity: [DayActivity]

    struct DayActivity: Codable {
        let date: String
        let messageCount: Int
        let sessionCount: Int
        let toolCallCount: Int
    }

    var todayStats: DayActivity? {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return dailyActivity.first { $0.date == String(today) }
    }
}

enum StatsCacheReader {
    private static let statsCachePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/stats-cache.json")

    static func parse(data: Data) throws -> StatsCache {
        return try JSONDecoder().decode(StatsCache.self, from: data)
    }

    static func readFromDisk() -> StatsCache? {
        guard let data = try? Data(contentsOf: statsCachePath) else { return nil }
        return try? parse(data: data)
    }
}
```

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add StatsCacheReader to parse ~/.claude/stats-cache.json"
```

---

### Task 6: Session Manager (Combines All Data Sources)

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Services/SessionManager.swift`

**Step 1: Write the failing test**

```swift
// SessionManagerTests.swift
import XCTest
@testable import ClaudeMonitorBar

final class SessionManagerTests: XCTestCase {
    func testSessionManagerStartsEmpty() {
        let manager = SessionManager()
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertFalse(manager.hasActiveSessions)
    }
}
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

```swift
// SessionManager.swift
import Foundation

@Observable
class SessionManager {
    var sessions: [ClaudeSession] = []
    var statsCache: StatsCache?

    private let processMonitor = ProcessMonitor()
    private var refreshTimer: Timer?

    var hasActiveSessions: Bool {
        !sessions.isEmpty
    }

    var totalTokensToday: Int {
        sessions.reduce(0) { $0 + $1.tokenCount }
    }

    var todayMessageCount: Int {
        statsCache?.todayStats?.messageCount ?? 0
    }

    var todaySessionCount: Int {
        statsCache?.todayStats?.sessionCount ?? 0
    }

    func startMonitoring() {
        processMonitor.startMonitoring()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stopMonitoring() {
        processMonitor.stopMonitoring()
        refreshTimer?.invalidate()
    }

    func refresh() {
        // 1. Get running PIDs
        processMonitor.refresh()
        let pids = processMonitor.runningPIDs

        // 2. Read debug logs for active sessions
        let debugDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/debug")
        let logFiles = (try? FileManager.default.contentsOfDirectory(
            at: debugDir, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        // Get recently modified log files (last 30 min)
        let recentLogs = logFiles.filter { url in
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate else { return false }
            return Date().timeIntervalSince(modDate) < 1800
        }

        // 3. Build sessions from recent logs + active PIDs
        var newSessions: [ClaudeSession] = []
        for logURL in recentLogs {
            let sessionId = DebugLogParser.sessionId(from: logURL.lastPathComponent)
            let tokens = DebugLogParser.latestTokenCount(from: logURL) ?? 0
            let attrs = try? logURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])

            let session = ClaudeSession(
                pid: pids.first ?? 0,
                projectPath: "~",  // Will enhance with history.jsonl lookup
                sessionId: sessionId,
                tokenCount: tokens,
                startTime: attrs?.creationDate ?? Date()
            )
            newSessions.append(session)
        }

        sessions = newSessions

        // 4. Read stats cache
        statsCache = StatsCacheReader.readFromDisk()
    }
}
```

**Step 4: Run tests, verify pass**

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add SessionManager combining process monitor, debug logs, and stats cache"
```

---

### Task 7: Menu Bar UI

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Views/MenuBarView.swift`
- Modify: `ClaudeMonitorBar/ClaudeMonitorBar/ClaudeMonitorBarApp.swift`

**Step 1: Create MenuBarView**

```swift
// MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let sessionManager: SessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if sessionManager.hasActiveSessions {
                Text("Active Sessions")
                    .font(.headline)
                    .padding(.horizontal, 8)

                ForEach(sessionManager.sessions) { session in
                    SessionRowView(session: session)
                }
            } else {
                Text("No active sessions")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }

            Divider()

            // Today's stats
            if let today = sessionManager.statsCache?.todayStats {
                Label("\(today.messageCount) messages today", systemImage: "message")
                    .padding(.horizontal, 8)
                Label("\(today.sessionCount) sessions today", systemImage: "terminal")
                    .padding(.horizontal, 8)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }
}

struct SessionRowView: View {
    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(session.projectName)
                    .fontWeight(.medium)
                Spacer()
                Text(session.durationFormatted)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            HStack {
                Text("\(session.tokenCount.formatted()) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("~$\(session.estimatedCost(inputRate: 15.0, outputRate: 75.0), specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
```

**Step 2: Update App.swift to use MenuBarView**

```swift
// ClaudeMonitorBarApp.swift
import SwiftUI

@main
struct ClaudeMonitorBarApp: App {
    @State private var sessionManager = SessionManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "sparkle")
                if sessionManager.hasActiveSessions {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: true) { _, _ in
            sessionManager.startMonitoring()
        }
    }
}
```

**Step 3: Build and run, verify UI appears**

Run: `xcodebuild -scheme ClaudeMonitorBar build`
Manual test: Click menu bar icon, see dropdown with session list.

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add menu bar UI with session list and daily stats"
```

---

### Task 8: History Parser — Map Sessions to Projects

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Services/HistoryParser.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBarTests/Services/HistoryParserTests.swift`

**Step 1: Write the failing test**

```swift
// HistoryParserTests.swift
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
```

**Step 2: Run test to verify it fails**

**Step 3: Write minimal implementation**

```swift
// HistoryParser.swift
import Foundation

enum HistoryParser {
    struct HistoryEntry: Codable {
        let project: String
        let sessionId: String
        let timestamp: Double

        enum CodingKeys: String, CodingKey {
            case project, sessionId, timestamp
        }
    }

    static func parseLine(_ jsonLine: String) throws -> HistoryEntry {
        let data = jsonLine.data(using: .utf8)!
        return try JSONDecoder().decode(HistoryEntry.self, from: data)
    }

    static func readHistory() -> [HistoryEntry] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/history.jsonl")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            try? parseLine(String(line))
        }
    }

    static func projectPath(forSession sessionId: String, in entries: [HistoryEntry]) -> String? {
        entries.last { $0.sessionId == sessionId }?.project
    }
}
```

**Step 4: Run tests, verify pass**

**Step 5: Update SessionManager to use HistoryParser**

In `SessionManager.refresh()`, after building sessions, look up project paths:

```swift
let historyEntries = HistoryParser.readHistory()
for i in newSessions.indices {
    if let path = HistoryParser.projectPath(forSession: newSessions[i].sessionId, in: historyEntries) {
        // Recreate with correct project path
        newSessions[i] = ClaudeSession(
            pid: newSessions[i].pid,
            projectPath: path,
            sessionId: newSessions[i].sessionId,
            tokenCount: newSessions[i].tokenCount,
            startTime: newSessions[i].startTime
        )
    }
}
```

**Step 6: Commit**

```bash
git add .
git commit -m "feat: add HistoryParser to map sessions to project paths"
```

---

### Task 9: Preferences View

**Files:**
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Views/PreferencesView.swift`
- Create: `ClaudeMonitorBar/ClaudeMonitorBar/Services/AppPreferences.swift`

**Step 1: Write AppPreferences**

```swift
// AppPreferences.swift
import Foundation

@Observable
class AppPreferences {
    static let shared = AppPreferences()

    var opusInputRate: Double {
        get { UserDefaults.standard.double(forKey: "opusInputRate").nonZero ?? 15.0 }
        set { UserDefaults.standard.set(newValue, forKey: "opusInputRate") }
    }

    var opusOutputRate: Double {
        get { UserDefaults.standard.double(forKey: "opusOutputRate").nonZero ?? 75.0 }
        set { UserDefaults.standard.set(newValue, forKey: "opusOutputRate") }
    }

    var refreshInterval: Double {
        get { UserDefaults.standard.double(forKey: "refreshInterval").nonZero ?? 5.0 }
        set { UserDefaults.standard.set(newValue, forKey: "refreshInterval") }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
```

**Step 2: Write PreferencesView**

```swift
// PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @Bindable var prefs = AppPreferences.shared

    var body: some View {
        Form {
            Section("Token Pricing (per 1M tokens)") {
                HStack {
                    Text("Opus Input:")
                    TextField("", value: $prefs.opusInputRate, format: .currency(code: "USD"))
                        .frame(width: 80)
                }
                HStack {
                    Text("Opus Output:")
                    TextField("", value: $prefs.opusOutputRate, format: .currency(code: "USD"))
                        .frame(width: 80)
                }
            }

            Section("General") {
                HStack {
                    Text("Refresh interval:")
                    TextField("", value: $prefs.refreshInterval, format: .number)
                        .frame(width: 50)
                    Text("seconds")
                }
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            }
        }
        .padding()
        .frame(width: 350)
    }
}
```

**Step 3: Add Preferences button to MenuBarView**

Add before Quit button:

```swift
Button("Preferences...") {
    NSApp.activate(ignoringOtherApps: true)
    // Open preferences window
}
```

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add preferences view with token pricing and launch at login"
```

---

### Task 10: Polish and Final Integration

**Files:**
- Modify: `ClaudeMonitorBar/ClaudeMonitorBar/ClaudeMonitorBarApp.swift`
- Modify: `ClaudeMonitorBar/ClaudeMonitorBar/Views/MenuBarView.swift`

**Step 1: Add cost summary to MenuBarView**

Add daily/monthly cost estimate section using `statsCache` data + token rates from preferences.

**Step 2: Add SF Symbol for menu bar icon**

Use `sparkle` or custom icon. Show green dot overlay when sessions active.

**Step 3: Full integration test**

1. Build and run app
2. Start a Claude Code session in terminal
3. Verify menu bar shows green dot
4. Click icon — see active session with project name, tokens, cost
5. Close Claude Code — verify dot turns gray

**Step 4: Commit**

```bash
git add .
git commit -m "feat: polish UI, add cost summary, final integration"
```

---

## Summary

| Task | Description | Est. Steps |
|------|-------------|------------|
| 1 | Xcode project skeleton | 4 |
| 2 | Data models + tests | 5 |
| 3 | Process monitor + tests | 5 |
| 4 | Debug log parser + tests | 5 |
| 5 | Stats cache reader + tests | 5 |
| 6 | Session manager | 5 |
| 7 | Menu bar UI | 4 |
| 8 | History parser + tests | 6 |
| 9 | Preferences view | 5 |
| 10 | Polish + integration | 4 |
