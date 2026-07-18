import SwiftUI

struct LimitRowView: View {
    let limit: UsageLimit

    var body: some View {
        HStack {
            Circle()
                .fill(limit.statusColor)
                .frame(width: 10, height: 10)

            Text(limit.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(limit.isRejected ? .red.opacity(0.9) : .white.opacity(0.9))

            if limit.isBinding {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(limit.statusColor.opacity(0.8))
                    .help("This limit currently constrains your usage")
            }

            Spacer()

            Text("\(Int(limit.percentage * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(limit.statusColor)

            Text(limit.resetTimeFormatted)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
