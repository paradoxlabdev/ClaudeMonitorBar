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

    func startMonitoring() {
        fetchUsage()
    }

    func stopMonitoring() {}

    /// Called when menu bar is opened - fetches fresh data
    func refresh() {
        fetchUsage()
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
                    self.overallPercentage = self.usageLimits.map(\.percentage).max() ?? 0
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
