import SwiftUI
import Charts

struct UsageChartView: View {
    let windows: [UsageWindow]
    let fiveHourReset: Int?
    let sevenDayReset: Int?
    var currentFiveHour: Double = 0
    var currentSevenDay: Double = 0

    /// Windows in the scroll viewport at once. The rest is reachable by scrolling.
    private static let visibleWindows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(
                kind: .fiveHour,
                title: "5-Hour Windows",
                dot: .green,
                reset: fiveHourReset,
                live: currentFiveHour,
                dateFormat: "HH:mm"
            )
            section(
                kind: .sevenDay,
                title: "7-Day Windows",
                dot: .orange,
                reset: sevenDayReset,
                live: currentSevenDay,
                dateFormat: "MMM d"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func section(
        kind: WindowKind,
        title: String,
        dot: Color,
        reset: Int?,
        live: Double,
        dateFormat: String
    ) -> some View {
        let points = points(kind: kind, reset: reset, live: live)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                // Without a count there is no hint that anything lies past the viewport.
                Text("· \(points.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
            }
            chart(points: points, kind: kind, dateFormat: dateFormat)
        }
    }

    @ViewBuilder
    private func chart(points: [UsageWindow], kind: WindowKind, dateFormat: String) -> some View {
        let visibleLength = Double(Self.visibleWindows) * kind.seconds
        let lastEnd = points.last?.end ?? Date()
        let firstEnd = points.first?.end ?? lastEnd
        // Half a window of padding on each side keeps the edge bars from being clipped,
        // and the domain is never shorter than one viewport or the scroll math degenerates.
        let domainEnd = lastEnd.addingTimeInterval(kind.seconds / 2)
        let domainStart = min(firstEnd, lastEnd.addingTimeInterval(-visibleLength))
            .addingTimeInterval(-kind.seconds / 2)
        let scrollStart = max(domainStart, domainEnd.addingTimeInterval(-visibleLength))

        Chart(points) { point in
            BarMark(
                x: .value("Window", point.end),
                y: .value("Usage", point.peak * 100),
                width: .fixed(22)
            )
            .foregroundStyle(barColor(point.peak))
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: domainStart...domainEnd)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(initialX: scrollStart)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)%")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: labelDates(points)) { value in
                // The edge marks sit half a window from the edge of the domain, which is
                // not enough room for a centred label — they render clipped. Anchoring
                // just those to the edge they touch lets them grow inwards instead.
                // Widening the domain would work too, but the empty slot it leaves at
                // the edge would read as a data gap.
                let anchor: UnitPoint = switch value.index {
                case 0: .topLeading
                case value.count - 1: .topTrailing
                default: .top
                }
                AxisValueLabel(anchor: anchor) {
                    if let date = value.as(Date.self) {
                        Text(Self.formatted(date, dateFormat))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .frame(height: 60)
    }

    /// Stored windows for `kind`, with the live reading folded into the in-progress
    /// window. Keeps the bar reacting immediately instead of waiting for a write, and
    /// keeps debug mode's mock values on the chart when nothing is stored yet.
    private func points(kind: WindowKind, reset: Int?, live: Double) -> [UsageWindow] {
        var result = windows.filter { $0.kind == kind }
        guard let reset, reset > 0 else { return result }

        let end = Date(timeIntervalSince1970: Double(reset))
        if let idx = result.lastIndex(where: {
            abs($0.end.timeIntervalSince(end)) < kind.seconds / 2
        }) {
            result[idx] = UsageWindow(kind: kind, end: end, peak: max(result[idx].peak, live))
        } else {
            result.append(UsageWindow(kind: kind, end: end, peak: live))
        }
        return result
    }

    /// Every second window end, anchored on the newest so the current window is labelled.
    /// Labelling all 8 visible bars makes "HH:mm" strings collide at 7 pt.
    private func labelDates(_ points: [UsageWindow]) -> [Date] {
        guard !points.isEmpty else { return [] }
        return Array(
            stride(from: points.count - 1, through: 0, by: -2)
                .map { points[$0].end }
                .reversed()
        )
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func barColor(_ value: Double) -> Color {
        if value >= 0.9 { return .statusRed }
        if value >= 0.7 { return .yellow }
        return .green
    }
}
