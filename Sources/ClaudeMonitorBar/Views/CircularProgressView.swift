import SwiftUI

struct CircularProgressView: View {
    let percentage: Double

    private var displayPercentage: Int {
        guard percentage.isFinite else { return 0 }
        return Int((min(max(percentage, 0), 1) * 100).rounded())
    }

    private var progressColor: Color {
        switch percentage {
        case ..<0.7: return .green
        case 0.7..<0.9: return .yellow
        case 0.9...: return .red
        default: return .gray
        }
    }

    private var gradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                progressColor.opacity(0.6),
                progressColor
            ]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * percentage)
        )
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)

            // Progress
            Circle()
                .trim(from: 0, to: percentage)
                .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: percentage)

            // Percentage text
            VStack(spacing: 2) {
                Text("\(displayPercentage)%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Used")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 90, height: 90)
    }
}
