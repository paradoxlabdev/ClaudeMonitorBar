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

    private var refreshTimer: Timer?

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
        startAutoRefresh()
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        fetchUsage()
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        let interval = max(AppPreferences.shared.refreshInterval * 60, 60) // minimum 1 min
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
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
            }
        }
    }
}
