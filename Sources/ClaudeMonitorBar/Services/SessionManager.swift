import Foundation

@Observable
class SessionManager {
    static let shared = SessionManager()

    var usageLimits: [UsageLimit] = []
    var overallPercentage: Double = 0
    var isLoading: Bool = false
    var lastFetchTime: Date?
    var fetchError: String?
    var rateLimited: Bool = false

    var planName: String?
    var subscriptionStatus: String?

    var overageStatus: String = ""
    var overageDisabledReason: String = ""

    var usageWindows: [UsageWindow] = []
    var localUsage: LocalUsageStats?

    // Debug mode
    var debugMode: Bool = false
    var mockFiveHour: Double = 0.3
    var mockSevenDay: Double = 0.5

    // Adaptive refresh state
    private var refreshTimer: Timer?
    private var unchangedCount: Int = 0
    private var previousUtilizations: (Double, Double)?

    var currentRefreshInterval: TimeInterval {
        adaptiveInterval
    }

    private var adaptiveInterval: TimeInterval {
        let base = AppPreferences.shared.refreshInterval * 60
        // Active: data changed recently → use base interval
        if unchangedCount < 3 { return max(base, 60) }
        // Short idle: no changes for 3 fetches → 2x base
        if unchangedCount < 6 { return max(base * 2, 120) }
        // Medium idle: no changes for 6 fetches → 3x base
        if unchangedCount < 12 { return max(base * 3, 180) }
        // Long idle: no changes for 12+ fetches → 5x base
        return max(base * 5, 300)
    }

    var statusColor: StatusColor {
        let pct = overallPercentage
        if pct >= 0.9 { return .red }
        if pct >= 0.7 { return .yellow }
        return .green
    }

    enum StatusColor {
        case green, yellow, red
    }

    func startMonitoring() {
        usageWindows = WindowHistory.shared.load()
        fetchUsage()
        scheduleNextRefresh()
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        unchangedCount = 0 // Manual refresh resets to active mode
        fetchUsage()
    }

    func startAutoRefresh() {
        scheduleNextRefresh()
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        let interval = adaptiveInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.fetchUsage()
        }
    }

    func applyMockData() {
        usageLimits = [
            UsageLimit(name: "Current session", utilization: mockFiveHour, resetTimestamp: Int(Date().addingTimeInterval(3600).timeIntervalSince1970), isBinding: mockFiveHour >= mockSevenDay),
            UsageLimit(name: "Current week", utilization: mockSevenDay, resetTimestamp: Int(Date().addingTimeInterval(86400).timeIntervalSince1970), isBinding: mockSevenDay > mockFiveHour)
        ]
        overallPercentage = mockFiveHour
        lastFetchTime = Date()
        fetchError = nil
    }

    private func fetchUsage() {
        guard !isLoading else { return }

        scanLocalUsage()

        if debugMode {
            applyMockData()
            scheduleNextRefresh()
            return
        }

        isLoading = true
        fetchError = nil

        Task {
            async let rateLimits = RateLimitFetcher.fetch()
            async let profile = RateLimitFetcher.fetchProfile()

            let data = await rateLimits
            let profileData = await profile

            await MainActor.run {
                self.isLoading = false
                self.lastFetchTime = Date()

                if let data {
                    self.fetchError = nil
                    self.rateLimited = data.status == "rate_limited"
                    self.usageLimits = [
                        UsageLimit(
                            name: "Current session",
                            utilization: data.fiveHourUtilization,
                            resetTimestamp: data.fiveHourReset,
                            isBinding: data.representativeClaim == "five_hour",
                            isRejected: data.fiveHourStatus == "rejected"
                        ),
                        UsageLimit(
                            name: "Current week",
                            utilization: data.sevenDayUtilization,
                            resetTimestamp: data.sevenDayReset,
                            isBinding: data.representativeClaim == "seven_day",
                            isRejected: data.sevenDayStatus == "rejected"
                        )
                    ]
                    self.overageStatus = data.overageStatus
                    self.overageDisabledReason = data.overageDisabledReason
                    self.overallPercentage = data.fiveHourUtilization

                    // Adaptive refresh: track if data changed
                    let current = (data.fiveHourUtilization, data.sevenDayUtilization)
                    if let prev = self.previousUtilizations,
                       abs(prev.0 - current.0) < 0.001,
                       abs(prev.1 - current.1) < 0.001 {
                        self.unchangedCount += 1
                    } else {
                        self.unchangedCount = 0
                    }
                    self.previousUtilizations = current

                    // Record the in-progress windows. A reset of 0 means the header was
                    // absent (see RateLimitFetcher's 429-without-headers path) — that is
                    // not a real window boundary, so skip it rather than stamping 1970.
                    let fiveEnd = data.fiveHourReset > 0
                        ? Date(timeIntervalSince1970: Double(data.fiveHourReset)) : nil
                    let sevenEnd = data.sevenDayReset > 0
                        ? Date(timeIntervalSince1970: Double(data.sevenDayReset)) : nil

                    // Must run before the first record() call, which would create the file
                    // and make the migration a no-op.
                    WindowHistory.shared.migrateIfNeeded(
                        snapshots: UsageHistory.load(),
                        fiveHourReset: fiveEnd,
                        sevenDayReset: sevenEnd
                    )

                    if let fiveEnd {
                        WindowHistory.shared.record(
                            kind: .fiveHour, end: fiveEnd, value: data.fiveHourUtilization
                        )
                    }
                    if let sevenEnd {
                        WindowHistory.shared.record(
                            kind: .sevenDay, end: sevenEnd, value: data.sevenDayUtilization
                        )
                    }
                    self.usageWindows = WindowHistory.shared.load()

                    // Check notifications
                    NotificationManager.checkAndNotify(limits: self.usageLimits)
                } else {
                    self.fetchError = "Unable to fetch usage data"
                }

                if let profileData {
                    self.planName = profileData.planName
                    self.subscriptionStatus = profileData.subscriptionStatus
                }

                // Schedule next adaptive refresh
                self.scheduleNextRefresh()
            }
        }
    }

    private var scanInFlight = false

    /// Aggregate token stats from local Claude Code logs, off the main thread.
    /// Coalesced: popover opens and refresh ticks can fire in bursts, so skip
    /// while a scan runs and re-use results younger than 30 s.
    private func scanLocalUsage() {
        guard !scanInFlight else { return }
        if let last = localUsage?.scannedAt, Date().timeIntervalSince(last) < 30 { return }
        scanInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            let stats = await LocalUsageScanner.shared.scan()
            await MainActor.run { [weak self] in
                self?.localUsage = stats
                self?.scanInFlight = false
            }
        }
    }
}
