import SwiftUI
import Charts

struct UsageChartView: View {
    let history: [UsageSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 5-Hour chart: last 5 windows (25h)
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

            // 7-Day chart: last 4 weeks
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

    // Sample one point per 5h window over last 25 hours
    private var fiveHourPoints: [ChartPoint] {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var points: [ChartPoint] = []

        for i in (0..<5).reversed() {
            let windowEnd = now.addingTimeInterval(-Double(i) * 5 * 3600)
            let windowStart = windowEnd.addingTimeInterval(-5 * 3600)
            // Find the latest snapshot in this window
            let snap = history
                .filter { $0.timestamp > windowStart && $0.timestamp <= windowEnd }
                .last
            let label = formatter.string(from: windowEnd)
            points.append(ChartPoint(label: label, value: snap?.fiveHourUtil ?? 0))
        }
        return points
    }

    // Sample one point per 7-day window over last 28 days
    private var sevenDayPoints: [ChartPoint] {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var points: [ChartPoint] = []

        for i in (0..<4).reversed() {
            let windowEnd = now.addingTimeInterval(-Double(i) * 7 * 86400)
            let windowStart = windowEnd.addingTimeInterval(-7 * 86400)
            let snap = history
                .filter { $0.timestamp > windowStart && $0.timestamp <= windowEnd }
                .last
            let label = formatter.string(from: windowEnd)
            points.append(ChartPoint(label: label, value: snap?.sevenDayUtil ?? 0))
        }
        return points
    }
}

private struct ChartPoint: Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}
