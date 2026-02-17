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
