import Foundation

struct DailyStats: Codable {
    let date: String  // "YYYY-MM-DD"
    var messageCount: Int
    var sessionCount: Int
    var toolCallCount: Int
    var estimatedTokens: Int
}
