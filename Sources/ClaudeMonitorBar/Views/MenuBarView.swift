import SwiftUI

struct MenuBarView: View {
    let sessionManager: SessionManager
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let url = Bundle.module.url(forResource: "claude-icon", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("Claude Monitor Bar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if let plan = sessionManager.planName {
                        Text("Plan: \(plan.replacingOccurrences(of: "Claude ", with: ""))")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if let renewal = sessionManager.renewalDate {
                        Text("Renews \(renewalFormatted(renewal))")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
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

                // Plan recommendation
                if sessionManager.usageLimits.count >= 2 {
                    let rec = PlanRecommendation.recommend(
                        currentPlan: sessionManager.planName,
                        sevenDayUtil: sessionManager.usageLimits[1].utilization,
                        sevenDayReset: sessionManager.usageLimits[1].resetTimestamp ?? 0,
                        fiveHourUtil: sessionManager.usageLimits[0].utilization,
                        fiveHourReset: sessionManager.usageLimits[0].resetTimestamp ?? 0
                    )
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: rec.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(rec.color)
                        VStack(alignment: .leading, spacing: 2) {
                            switch rec.action {
                            case .downgrade(let to, let price):
                                Text("Consider \(to) (\(price))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(rec.color)
                            case .stay:
                                Text("Plan fits your usage")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(rec.color)
                            case .upgrade(let to, let price):
                                Text("Consider \(to) (\(price))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(rec.color)
                            }
                            Text(rec.reason)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                }

                // Usage history chart
                if !sessionManager.usageHistory.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.top, 8)

                    UsageChartView(
                        history: sessionManager.usageHistory,
                        fiveHourReset: sessionManager.usageLimits.first?.resetTimestamp,
                        sevenDayReset: sessionManager.usageLimits.count >= 2 ? sessionManager.usageLimits[1].resetTimestamp : nil
                    )
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
                    let secs = Int(sessionManager.currentRefreshInterval)
                    let label = secs >= 120 ? "\(secs / 60)min" : "\(secs)s"
                    Text("Refresh: \(label)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            // Settings (collapsible)
            if showSettings {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.top, 6)

                SettingsSection()
            }

            // Update banner
            if let progress = UpdateChecker.shared.downloadProgress {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Updating...")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.cyan)
                    ProgressView(value: progress)
                        .tint(.cyan)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.08))
            } else if UpdateChecker.shared.updateAvailable, let version = UpdateChecker.shared.latestVersion {
                Button(action: {
                    UpdateChecker.shared.performUpdate()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                        Text("Update available: v\(version)")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Install")
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.08))
                }
                .buttonStyle(.plain)
            }

            // Bottom bar
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
                    .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { withAnimation { showSettings.toggle() } }) {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(showSettings ? 0.5 : 0.25))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://paradoxlab.dev/")!)
                }) {
                    Text("v\(UpdateChecker.currentVersion) · paradoxlab.dev")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.2))
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
                    .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
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

struct SettingsSection: View {
    private let prefs = AppPreferences.shared
    @State private var refreshInterval: Double = AppPreferences.shared.refreshInterval
    @State private var notificationsOn: Bool = AppPreferences.shared.notificationsEnabled
    @State private var launchAtLogin: Bool = AppPreferences.shared.launchAtLogin
    @State private var iconStyle: String = AppPreferences.shared.iconStyle

    private let intervals: [(String, Double)] = [
        ("1 min", 1), ("5 min", 5), ("10 min", 10), ("30 min", 30)
    ]
    private let iconStyles: [(String, String)] = [
        ("Auto", "auto"), ("Light", "light"), ("Dark", "dark")
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "bell")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Notifications")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Toggle("", isOn: $notificationsOn)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .onChange(of: notificationsOn) { _, val in
                        prefs.notificationsEnabled = val
                    }
            }

            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Refresh every")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                HStack(spacing: 4) {
                    ForEach(intervals, id: \.1) { label, value in
                        Button(action: {
                            refreshInterval = value
                            prefs.refreshInterval = value
                        }) {
                            Text(label)
                                .font(.system(size: 9, weight: refreshInterval == value ? .bold : .regular))
                                .foregroundStyle(refreshInterval == value ? .white.opacity(0.7) : .white.opacity(0.25))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(refreshInterval == value ? Color.white.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Image(systemName: "circle.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Icon style")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                HStack(spacing: 4) {
                    ForEach(iconStyles, id: \.1) { label, value in
                        Button(action: {
                            iconStyle = value
                            prefs.iconStyle = value
                        }) {
                            Text(label)
                                .font(.system(size: 9, weight: iconStyle == value ? .bold : .regular))
                                .foregroundStyle(iconStyle == value ? .white.opacity(0.7) : .white.opacity(0.25))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(iconStyle == value ? Color.white.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Image(systemName: "play.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Launch at Login")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .onChange(of: launchAtLogin) { _, val in
                        prefs.launchAtLogin = val
                    }
            }

            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Updates")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button(action: { UpdateChecker.shared.check() }) {
                    let uc = UpdateChecker.shared
                    let label = uc.updateAvailable
                        ? "v\(uc.latestVersion ?? "") available"
                        : uc.upToDate ? "Up to date" : "Check now"
                    let color: Color = uc.updateAvailable
                        ? .cyan
                        : uc.upToDate ? .green : .white.opacity(0.5)
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
