import SwiftUI
import Charts

struct UsageChartView: View {
    let history: [UsageSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage History (7 days)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Chart {
                ForEach(recent) { snap in
                    LineMark(
                        x: .value("Time", snap.timestamp),
                        y: .value("Usage", snap.fiveHourUtil * 100),
                        series: .value("Limit", "5h")
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    LineMark(
                        x: .value("Time", snap.timestamp),
                        y: .value("Usage", snap.sevenDayUtil * 100),
                        series: .value("Limit", "7d")
                    )
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)%")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(.white.opacity(0.3))
                        .font(.system(size: 8))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 80)

            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("5-Hour").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                }
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("7-Day").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var recent: [UsageSnapshot] {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return history.filter { $0.timestamp > cutoff }
    }
}
