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
