import SwiftUI
import ServiceManagement

@main
struct ClaudeMonitorBarApp: App {
    @State private var sessionManager = SessionManager.shared

    init() {
        NotificationManager.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SessionManager.shared.startMonitoring()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(sessionManager: sessionManager)
        } label: {
            MenuBarIcon(statusColor: sessionManager.statusColor)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarIcon: View {
    let statusColor: SessionManager.StatusColor

    private var color: Color {
        switch statusColor {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 1.5

                // Background ring
                let bgPath = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                context.stroke(bgPath, with: .color(.gray.opacity(0.3)), lineWidth: 2)

                // Progress arc
                let progress = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(-90),
                             endAngle: .degrees(-90 + 360 * 0.66),
                             clockwise: false)
                }
                context.stroke(progress, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // ">_" text
                let text = Text(">_")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                context.draw(text, at: center)
            }
            .frame(width: 16, height: 16)
        }
    }
}
