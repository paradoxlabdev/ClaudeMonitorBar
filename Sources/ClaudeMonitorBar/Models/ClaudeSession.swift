import Foundation

struct ClaudeSession: Identifiable {
    let id: String
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
        Double(tokenCount) / 1_000_000.0 * inputRate
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
