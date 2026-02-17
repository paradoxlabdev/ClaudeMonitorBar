import Foundation

struct StatsCache: Codable {
    let version: Int
    let lastComputedDate: String
    let dailyActivity: [DayActivity]
    let dailyModelTokens: [DailyModelTokens]?
    let modelUsage: [String: ModelUsage]?
    let totalSessions: Int?
    let totalMessages: Int?

    struct DayActivity: Codable {
        let date: String
        let messageCount: Int
        let sessionCount: Int
        let toolCallCount: Int
    }

    struct DailyModelTokens: Codable {
        let date: String
        let tokensByModel: [String: Int]
    }

    struct ModelUsage: Codable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadInputTokens: Int
        let cacheCreationInputTokens: Int

        /// Effective tokens: input + output + cacheCreate + cacheRead*0.1
        var effectiveTokens: Int {
            inputTokens + outputTokens + cacheCreationInputTokens + (cacheReadInputTokens / 10)
        }
    }

    /// Total effective Opus tokens (all-time)
    var totalOpusEffectiveTokens: Int {
        modelUsage?.filter { $0.key.contains("opus") }
            .values.map(\.effectiveTokens).reduce(0, +) ?? 0
    }

    /// Total effective Sonnet tokens (all-time)
    var totalSonnetEffectiveTokens: Int {
        modelUsage?.filter { $0.key.contains("sonnet") }
            .values.map(\.effectiveTokens).reduce(0, +) ?? 0
    }

    /// Output tokens for Opus on a specific date
    func opusOutputTokens(for date: String) -> Int {
        dailyModelTokens?.first { $0.date == date }?
            .tokensByModel
            .filter { $0.key.contains("opus") }
            .values.reduce(0, +) ?? 0
    }

    /// Output tokens for Sonnet on a specific date
    func sonnetOutputTokens(for date: String) -> Int {
        dailyModelTokens?.first { $0.date == date }?
            .tokensByModel
            .filter { $0.key.contains("sonnet") }
            .values.reduce(0, +) ?? 0
    }

    /// Sum output tokens over last N days
    func opusOutputTokensLastDays(_ days: Int, from referenceDate: Date = Date()) -> Int {
        sumTokensLastDays(days, from: referenceDate, extractor: opusOutputTokens)
    }

    func sonnetOutputTokensLastDays(_ days: Int, from referenceDate: Date = Date()) -> Int {
        sumTokensLastDays(days, from: referenceDate, extractor: sonnetOutputTokens)
    }

    /// Messages in last N days
    func messagesLastDays(_ days: Int, from referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var total = 0
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) else { continue }
            let dateStr = formatter.string(from: date)
            total += dailyActivity.first { $0.date == dateStr }?.messageCount ?? 0
        }
        return total
    }

    /// Today's stats
    var todayStats: DayActivity? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return dailyActivity.first { $0.date == today }
    }

    private func sumTokensLastDays(_ days: Int, from referenceDate: Date, extractor: (String) -> Int) -> Int {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var total = 0
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: referenceDate) else { continue }
            let dateStr = formatter.string(from: date)
            total += extractor(dateStr)
        }
        return total
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
