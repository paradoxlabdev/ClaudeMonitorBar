import SwiftUI

struct MenuBarView: View {
    let sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Claude Usage")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(sessionManager.planName ?? AppPreferences.shared.planTier.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if sessionManager.isLoading && sessionManager.usageLimits.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .padding(.vertical, 30)
            } else if let error = sessionManager.fetchError, sessionManager.usageLimits.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
            } else {
                // Circular progress ring
                CircularProgressView(percentage: sessionManager.overallPercentage)
                    .padding(.vertical, 12)

                // Limit rows
                VStack(spacing: 2) {
                    ForEach(sessionManager.usageLimits) { limit in
                        LimitRowView(limit: limit)
                    }
                }
                .padding(.vertical, 8)

                // Subscription renewal
                if let renewal = sessionManager.renewalDate {
                    HStack {
                        Image(systemName: "creditcard")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Renews \(renewalFormatted(renewal))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                // Footer
                HStack {
                    if sessionManager.isLoading {
                        Text("Refreshing...")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    } else if let lastFetch = sessionManager.lastFetchTime {
                        Text("Updated \(lastFetch.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            // Bottom bar: Refresh + Quit
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.top, 8)

            HStack {
                Button(action: { sessionManager.refresh() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Refresh")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 4) {
                        Text("Quit")
                            .font(.system(size: 12))
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
        .background(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)))
        .onAppear {
            sessionManager.refresh()
        }
    }

    private func renewalFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
