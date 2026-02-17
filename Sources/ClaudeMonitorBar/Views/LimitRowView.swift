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
                .foregroundStyle(.white.opacity(0.9))

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
