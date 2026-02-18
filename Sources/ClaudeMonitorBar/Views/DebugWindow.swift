import SwiftUI
import AppKit

@Observable
class DebugWindowController {
    static let shared = DebugWindowController()
    var isOpen = false
    private var window: NSWindow?

    func toggle(sessionManager: SessionManager) {
        if isOpen {
            close()
        } else {
            open(sessionManager: sessionManager)
        }
    }

    func open(sessionManager: SessionManager) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        sessionManager.debugMode = true
        sessionManager.applyMockData()

        let view = DebugWindowView(sessionManager: sessionManager, onClose: { [weak self] in
            self?.close()
        })
        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Debug Mode"
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.center()
        // Shift left so it doesn't overlap the menu bar popup
        if let frame = panel.screen?.visibleFrame {
            var origin = panel.frame.origin
            origin.x = frame.minX + frame.width * 0.375 - panel.frame.width / 2
            panel.setFrameOrigin(origin)
        }

        // Observe window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.isOpen = false
            self?.window = nil
            sessionManager.debugMode = false
            sessionManager.refresh()
        }

        window = panel
        isOpen = true

        // Show without stealing focus from MenuBarExtra popup
        DispatchQueue.main.async {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        window?.close()
        window = nil
        isOpen = false
    }
}

struct DebugWindowView: View {
    let sessionManager: SessionManager
    let onClose: () -> Void
    @State private var apiLog = APILog.shared

    var body: some View {
        VStack(spacing: 12) {
            // Mock data sliders
            VStack(spacing: 8) {
                Text("Mock Data")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)

                sliderRow("5-Hour", value: Binding(
                    get: { sessionManager.mockFiveHour },
                    set: { sessionManager.mockFiveHour = $0; sessionManager.applyMockData() }
                ))
                sliderRow("7-Day", value: Binding(
                    get: { sessionManager.mockSevenDay },
                    set: { sessionManager.mockSevenDay = $0; sessionManager.applyMockData() }
                ))
                sliderRow("Sonnet", value: Binding(
                    get: { sessionManager.mockSonnet },
                    set: { sessionManager.mockSonnet = $0; sessionManager.applyMockData() }
                ))
            }

            // Rate limited toggle
            HStack {
                Text("Rate Limited")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { sessionManager.rateLimited },
                    set: { sessionManager.rateLimited = $0 }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
            }

            Divider().background(Color.white.opacity(0.1))

            // Force notification button
            Button(action: {
                NotificationManager.forceTestNotification()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 11))
                    Text("Send Test Notification")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.orange.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Divider().background(Color.white.opacity(0.1))

            // API Log
            VStack(alignment: .leading, spacing: 4) {
                Text("API Log")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))

                if apiLog.entries.isEmpty {
                    Text("No API calls yet")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(apiLog.entries) { entry in
                                HStack(spacing: 6) {
                                    Text(Self.timeFormatter.string(from: entry.timestamp))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.25))
                                    Text(entry.endpoint)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    Text("\(entry.statusCode)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(entry.statusCode == 200 ? .green.opacity(0.7) : .red.opacity(0.7))
                                    Text(String(format: "%.0fms", entry.duration * 1000))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                if let error = entry.error {
                                    Text(error)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.red.opacity(0.5))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 280, minHeight: 300)
        .background(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 45, alignment: .leading)
            Slider(value: value, in: 0...1, step: 0.01)
                .tint(.orange)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 32, alignment: .trailing)
        }
    }
}
