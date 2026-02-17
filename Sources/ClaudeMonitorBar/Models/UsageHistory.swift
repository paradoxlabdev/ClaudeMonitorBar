import Foundation

struct UsageSnapshot: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let fiveHourUtil: Double
    let sevenDayUtil: Double
    let sevenDaySonnetUtil: Double
}

enum UsageHistory {
    private static let maxDays = 30

    static var storageURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

    static func append(_ snapshot: UsageSnapshot) {
        var history = load()

        // Don't save more than once per 5 minutes
        if let last = history.last,
           snapshot.timestamp.timeIntervalSince(last.timestamp) < 300 {
            return
        }

        history.append(snapshot)

        // Trim to last N days
        let cutoff = Date().addingTimeInterval(-Double(maxDays) * 86400)
        history = history.filter { $0.timestamp > cutoff }

        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: storageURL)
        }
    }
}
