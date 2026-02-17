import Foundation
import Security

/// Fetches real rate limit data by making a minimal API call with the OAuth token.
/// Same approach as Claude Code's /usage command internally.
enum RateLimitFetcher {

    struct RateLimitData {
        let fiveHourUtilization: Double
        let fiveHourReset: Int
        let sevenDayUtilization: Double
        let sevenDayReset: Int
        let sevenDaySonnetUtilization: Double
        let sevenDaySonnetReset: Int
        let status: String
    }

    struct ProfileData {
        let planName: String           // e.g. "Claude Max 5x"
        let subscriptionStatus: String // e.g. "active"
        let renewalDate: Date?         // next billing date
    }

    /// Fetch profile/subscription info from the OAuth profile endpoint.
    static func fetchProfile() async -> ProfileData? {
        guard let token = readAccessToken() else { return nil }

        let url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let org = json["organization"] as? [String: Any] else {
            return nil
        }

        let orgType = org["organization_type"] as? String ?? ""
        let rateLimitTier = org["rate_limit_tier"] as? String ?? ""
        let subStatus = org["subscription_status"] as? String ?? "unknown"
        let subCreatedAt = org["subscription_created_at"] as? String

        // Build plan name
        let planName: String
        if rateLimitTier.contains("20x") {
            planName = "Claude Max 20x"
        } else if rateLimitTier.contains("5x") {
            planName = "Claude Max 5x"
        } else if orgType.contains("max") {
            planName = "Claude Max"
        } else if orgType.contains("pro") {
            planName = "Claude Pro"
        } else {
            planName = orgType
        }

        // Calculate next renewal: subscription_created_at + N months (next future date)
        var renewalDate: Date?
        if let createdStr = subCreatedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let createdDate = formatter.date(from: createdStr) {
                let calendar = Calendar.current
                let now = Date()
                // Find the next monthly anniversary
                var candidate = createdDate
                while candidate <= now {
                    candidate = calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate.addingTimeInterval(30 * 86400)
                }
                renewalDate = candidate
            }
        }

        return ProfileData(
            planName: planName,
            subscriptionStatus: subStatus,
            renewalDate: renewalDate
        )
    }

    /// Fetch rate limits by making a minimal Messages API call (max_tokens=1).
    /// Returns nil if auth fails or network error.
    static func fetch() async -> RateLimitData? {
        guard let token = readAccessToken() else { return nil }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "q"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        let headers = httpResponse.allHeaderFields

        func headerDouble(_ key: String) -> Double {
            if let val = headers[key] as? String {
                return Double(val) ?? 0
            }
            return 0
        }

        func headerInt(_ key: String) -> Int {
            if let val = headers[key] as? String {
                return Int(val) ?? 0
            }
            return 0
        }

        // Headers are case-insensitive in HTTPURLResponse
        let h5util = headerDouble("anthropic-ratelimit-unified-5h-utilization")
        let h5reset = headerInt("anthropic-ratelimit-unified-5h-reset")
        let d7util = headerDouble("anthropic-ratelimit-unified-7d-utilization")
        let d7reset = headerInt("anthropic-ratelimit-unified-7d-reset")
        let s7util = headerDouble("anthropic-ratelimit-unified-7d_sonnet-utilization")
        let s7reset = headerInt("anthropic-ratelimit-unified-7d_sonnet-reset")
        let status = headers["anthropic-ratelimit-unified-status"] as? String ?? "unknown"

        return RateLimitData(
            fiveHourUtilization: h5util,
            fiveHourReset: h5reset,
            sevenDayUtilization: d7util,
            sevenDayReset: d7reset,
            sevenDaySonnetUtilization: s7util,
            sevenDaySonnetReset: s7reset,
            status: status
        )
    }

    /// Read the OAuth access token from Keychain
    private static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    }
}
