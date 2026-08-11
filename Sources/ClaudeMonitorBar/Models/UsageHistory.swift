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
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
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
