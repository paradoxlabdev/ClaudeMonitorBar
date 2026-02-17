import Foundation

@Observable
class SessionManager {
    static let shared = SessionManager()

    var usageLimits: [UsageLimit] = []
    var overallPercentage: Double = 0
    var isLoading: Bool = false
    var lastFetchTime: Date?
    var fetchError: String?

    var planName: String?
    var subscriptionStatus: String?
    var renewalDate: Date?

    var usageHistory: [UsageSnapshot] = []

    // Adaptive refresh state
    private var refreshTimer: Timer?
    private var unchangedCount: Int = 0
    private var previousUtilizations: (Double, Double, Double)?

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
        usageHistory = UsageHistory.load()
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

    private func fetchUsage() {
        guard !isLoading else { return }
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
                    self.usageLimits = [
                        UsageLimit(
                            name: "5-Hour Limit",
                            utilization: data.fiveHourUtilization,
                            resetTimestamp: data.fiveHourReset
                        ),
                        UsageLimit(
                            name: "7-Day Limit",
                            utilization: data.sevenDayUtilization,
                            resetTimestamp: data.sevenDayReset
                        ),
                        UsageLimit(
                            name: "7D Sonnet Limit",
                            utilization: data.sevenDaySonnetUtilization,
                            resetTimestamp: data.sevenDaySonnetReset
                        )
                    ]
                    self.overallPercentage = data.fiveHourUtilization

                    // Adaptive refresh: track if data changed
                    let current = (data.fiveHourUtilization, data.sevenDayUtilization, data.sevenDaySonnetUtilization)
                    if let prev = self.previousUtilizations,
                       abs(prev.0 - current.0) < 0.001,
                       abs(prev.1 - current.1) < 0.001,
                       abs(prev.2 - current.2) < 0.001 {
                        self.unchangedCount += 1
                    } else {
                        self.unchangedCount = 0
                    }
                    self.previousUtilizations = current

                    // Save to history
                    let snapshot = UsageSnapshot(
                        timestamp: Date(),
                        fiveHourUtil: data.fiveHourUtilization,
                        sevenDayUtil: data.sevenDayUtilization,
                        sevenDaySonnetUtil: data.sevenDaySonnetUtilization
                    )
                    UsageHistory.append(snapshot)
                    self.usageHistory = UsageHistory.load()

                    // Check notifications
                    NotificationManager.checkAndNotify(limits: self.usageLimits)
                } else {
                    self.fetchError = "Unable to fetch usage data"
                }

                if let profileData {
                    self.planName = profileData.planName
                    self.subscriptionStatus = profileData.subscriptionStatus
                    self.renewalDate = profileData.renewalDate
                }

                // Schedule next adaptive refresh
                self.scheduleNextRefresh()
            }
        }
    }
}
