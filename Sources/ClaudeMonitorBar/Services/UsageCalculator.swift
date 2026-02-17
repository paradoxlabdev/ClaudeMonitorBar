import Foundation

/// Legacy usage calculator - kept for potential offline fallback.
/// Primary usage data now comes from RateLimitFetcher.
enum UsageCalculator {

    /// Sum token counts from recent debug log files
    static func tokensFromRecentDebugLogs(withinHours hours: Int = 5) -> Int {
        let debugDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/debug")
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: debugDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }

        var totalTokens = 0
        for fileURL in files {
            guard fileURL.pathExtension == "txt",
                  let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate,
                  modDate > cutoff else { continue }

            if let tokens = DebugLogParser.latestTokenCount(from: fileURL) {
                totalTokens += tokens
            }
        }
        return totalTokens
    }
}
