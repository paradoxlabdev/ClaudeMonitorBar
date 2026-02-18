import SwiftUI

struct UsageLimit: Identifiable {
    let id = UUID()
    let name: String
    let utilization: Double  // 0.0 to 1.0 from API header
    let resetTimestamp: Int? // Unix timestamp from API header

    var percentage: Double {
        min(max(utilization, 0), 1.0)
    }

    var statusColor: Color {
        switch percentage {
        case ..<0.7: return .green
        case 0.7..<0.9: return .yellow
        case 0.9...: return .red
        default: return .gray
        }
    }

    var resetTimeFormatted: String {
        guard let ts = resetTimestamp else { return "—" }
        let date = Date(timeIntervalSince1970: Double(ts))
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: date))"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d h:mm a"
        return formatter.string(from: date)
    }
}
