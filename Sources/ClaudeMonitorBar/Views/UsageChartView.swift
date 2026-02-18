import SwiftUI
import Charts

struct UsageChartView: View {
    let history: [UsageSnapshot]
    let fiveHourReset: Int?
    let sevenDayReset: Int?
    var currentFiveHour: Double = 0
    var currentSevenDay: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 5-Hour chart: last 5 windows aligned to reset
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("5-Hour Windows")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Chart {
                    ForEach(fiveHourPoints) { point in
                        BarMark(
                            x: .value("Window", point.label),
                            y: .value("Usage", point.value * 100)
                        )
                        .foregroundStyle(barColor(point.value))
                        .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            Text("\(value.as(Int.self) ?? 0)%")
                                .font(.system(size: 7))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .frame(height: 60)
            }

            // 7-Day chart: last 4 windows aligned to reset
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("7-Day Windows")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Chart {
                    ForEach(sevenDayPoints) { point in
                        BarMark(
                            x: .value("Window", point.label),
                            y: .value("Usage", point.value * 100)
                        )
                        .foregroundStyle(barColor(point.value))
                        .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            Text("\(value.as(Int.self) ?? 0)%")
                                .font(.system(size: 7))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 7))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .frame(height: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func barColor(_ value: Double) -> Color {
        if value >= 0.9 { return .red }
        if value >= 0.7 { return .yellow }
        return .green
    }

    // Windows aligned to the API reset time
    // Reset = end of current window, so current window started at (reset - 5h)
    // Previous windows go back in 5h steps from there
    private var fiveHourPoints: [ChartPoint] {
        let windowSeconds: TimeInterval = 5 * 3600
        let resetDate: Date
        if let ts = fiveHourReset {
            resetDate = Date(timeIntervalSince1970: Double(ts))
        } else {
            // Fallback: round up to nearest 5h boundary
            resetDate = Date()
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var points: [ChartPoint] = []

        for i in (0..<5).reversed() {
            let windowEnd = resetDate.addingTimeInterval(-Double(i) * windowSeconds)
            let windowStart = windowEnd.addingTimeInterval(-windowSeconds)
            let snap = history
                .filter { $0.timestamp > windowStart && $0.timestamp <= windowEnd }
                .last
            let label = formatter.string(from: windowEnd)
            // Current window: use live value
            let value = (i == 0) ? currentFiveHour : (snap?.fiveHourUtil ?? 0)
            points.append(ChartPoint(label: label, value: value))
        }
        return points
    }

    // Windows aligned to the API 7-day reset time
    private var sevenDayPoints: [ChartPoint] {
        let windowSeconds: TimeInterval = 7 * 86400
        let resetDate: Date
        if let ts = sevenDayReset {
            resetDate = Date(timeIntervalSince1970: Double(ts))
        } else {
            resetDate = Date()
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var points: [ChartPoint] = []

        for i in (0..<4).reversed() {
            let windowEnd = resetDate.addingTimeInterval(-Double(i) * windowSeconds)
            let windowStart = windowEnd.addingTimeInterval(-windowSeconds)
            let snap = history
                .filter { $0.timestamp > windowStart && $0.timestamp <= windowEnd }
                .last
            let label = formatter.string(from: windowEnd)
            let value = (i == 0) ? currentSevenDay : (snap?.sevenDayUtil ?? 0)
            points.append(ChartPoint(label: label, value: value))
        }
        return points
    }
}

private struct ChartPoint: Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}
