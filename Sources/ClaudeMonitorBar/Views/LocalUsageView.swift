import SwiftUI

/// Collapsible section showing per-model token usage aggregated from local
/// Claude Code session logs.
struct LocalUsageView: View {
    let stats: LocalUsageStats
    @State private var showWeek = false
    @State private var expanded = true

    private var rows: [ModelUsage] { showWeek ? stats.week : stats.today }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: { withAnimation { expanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Local usage")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                if expanded {
                    HStack(spacing: 4) {
                        periodButton("Today", selected: !showWeek) { showWeek = false }
                        periodButton("7 days", selected: showWeek) { showWeek = true }
                    }
                }
            }

            if expanded {
                if rows.isEmpty {
                    Text("No activity")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let totalOut = rows.reduce(0) { $0 + $1.outputTokens }

                    VStack(spacing: 3) {
                        ForEach(rows) { row in
                            HStack(spacing: 6) {
                                Text(row.model)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text("\(row.messages) msgs")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.3))
                                Spacer()
                                if totalOut > 0 {
                                    Text("\(Int((Double(row.outputTokens) / Double(totalOut) * 100).rounded()))%")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                Text("\(Self.formatTokens(row.outputTokens)) out")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .layoutPriority(1)
                            }
                        }
                    }

                    let totalIn = rows.reduce(0) { $0 + $1.inputTokens }
                    let totalCache = rows.reduce(0) { $0 + $1.cacheTokens }
                    HStack {
                        Text("In \(Self.formatTokens(totalIn)) · Out \(Self.formatTokens(totalOut)) · Cache \(Self.formatTokens(totalCache))")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.25))
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func periodButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? .white.opacity(0.7) : .white.opacity(0.25))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(selected ? Color.white.opacity(0.1) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    static func formatTokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
}
