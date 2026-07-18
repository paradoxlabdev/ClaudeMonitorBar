import Foundation

struct ModelUsage: Identifiable {
    var id: String { model }
    let model: String
    var messages: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheTokens: Int = 0
}

struct LocalUsageStats {
    let today: [ModelUsage]
    let week: [ModelUsage]
    let scannedAt: Date

    var isEmpty: Bool { week.isEmpty }
}

/// Scans Claude Code session logs (~/.claude/projects/**/*.jsonl) and aggregates
/// per-model token usage for today and the last 7 calendar days.
///
/// Files are cached by (mtime, size) so repeated scans only re-parse sessions
/// that changed since the last scan.
actor LocalUsageScanner {
    static let shared = LocalUsageScanner()

    private struct MessageRecord {
        let dedupKey: String
        let ts: Date         // raw message timestamp; day-bucketed at scan time
                             // so cached records survive a system timezone change
        let model: String    // normalized display name
        let input: Int
        let output: Int
        let cache: Int
    }

    private struct FileCache {
        let mtime: Date
        let size: Int
        let records: [MessageRecord]
    }

    private let root: URL
    private var cache: [String: FileCache] = [:]

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func scan(now: Date = Date()) -> LocalUsageStats {
        let fm = FileManager.default
        // File-level cutoff is 8 days so every message in the 7-day window is covered
        let fileCutoff = now.addingTimeInterval(-8 * 86400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]

        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return LocalUsageStats(today: [], week: [], scannedAt: now)
        }

        var records: [MessageRecord] = []
        var seenPaths: Set<String> = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate,
                  let size = values.fileSize,
                  mtime > fileCutoff else { continue }

            let path = url.path
            seenPaths.insert(path)
            if let cached = cache[path], cached.mtime == mtime, cached.size == size {
                records.append(contentsOf: cached.records)
            } else {
                let parsed = Self.parseFile(at: url)
                cache[path] = FileCache(mtime: mtime, size: size, records: parsed)
                records.append(contentsOf: parsed)
            }
        }

        // Drop cache entries for files that aged out or were deleted
        cache = cache.filter { seenPaths.contains($0.key) }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart

        // Global dedupe across files: resumed/forked sessions copy history
        var seenKeys: Set<String> = []
        var todayAgg: [String: ModelUsage] = [:]
        var weekAgg: [String: ModelUsage] = [:]

        func add(_ rec: MessageRecord, to agg: inout [String: ModelUsage]) {
            var entry = agg[rec.model] ?? ModelUsage(model: rec.model)
            entry.messages += 1
            entry.inputTokens += rec.input
            entry.outputTokens += rec.output
            entry.cacheTokens += rec.cache
            agg[rec.model] = entry
        }

        for rec in records {
            guard seenKeys.insert(rec.dedupKey).inserted else { continue }
            let day = calendar.startOfDay(for: rec.ts)
            guard day >= weekStart, day <= todayStart else { continue }
            add(rec, to: &weekAgg)
            if day == todayStart {
                add(rec, to: &todayAgg)
            }
        }

        func sorted(_ agg: [String: ModelUsage]) -> [ModelUsage] {
            agg.values.sorted {
                if $0.outputTokens != $1.outputTokens { return $0.outputTokens > $1.outputTokens }
                return $0.model < $1.model
            }
        }

        return LocalUsageStats(today: sorted(todayAgg), week: sorted(weekAgg), scannedAt: now)
    }

    // MARK: - Parsing

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseFile(at url: URL) -> [MessageRecord] {
        // Byte-level line walk: avoids materializing the whole file as String
        // plus a per-line Data copy, which tripled peak memory and parse time
        guard let data = try? Data(contentsOf: url) else { return [] }

        let newline = UInt8(ascii: "\n")
        let needle = Data("assistant".utf8)
        var result: [MessageRecord] = []
        var start = data.startIndex

        while start < data.endIndex {
            let end = data[start...].firstIndex(of: newline) ?? data.endIndex
            if end > start {
                let line = data.subdata(in: start..<end)
                // Cheap prefilter before JSON decoding; the parsed type check is authoritative
                if line.range(of: needle) != nil,
                   let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let rec = record(from: obj) {
                    result.append(rec)
                }
            }
            start = end < data.endIndex ? data.index(after: end) : data.endIndex
        }
        return result
    }

    private static func record(from obj: [String: Any]) -> MessageRecord? {
        guard obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let rawModel = message["model"] as? String,
              let model = normalizedModel(rawModel),
              let tsString = obj["timestamp"] as? String,
              let ts = isoFractional.date(from: tsString) ?? isoPlain.date(from: tsString)
        else { return nil }

        let msgId = message["id"] as? String
        let reqId = obj["requestId"] as? String
        let dedupKey = (msgId != nil || reqId != nil)
            ? "\(msgId ?? "")|\(reqId ?? "")"
            : UUID().uuidString

        return MessageRecord(
            dedupKey: dedupKey,
            ts: ts,
            model: model,
            input: usage["input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            cache: (usage["cache_creation_input_tokens"] as? Int ?? 0)
                + (usage["cache_read_input_tokens"] as? Int ?? 0)
        )
    }

    /// Collapse model ids and bare aliases into family buckets; nil = skip the entry.
    static func normalizedModel(_ raw: String) -> String? {
        if raw.isEmpty || raw == "<synthetic>" { return nil }
        let lower = raw.lowercased()
        if lower.contains("fable") { return "Fable" }
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return raw
    }
}
