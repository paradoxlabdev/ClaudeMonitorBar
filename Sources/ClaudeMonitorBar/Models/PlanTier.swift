import Foundation
import Security

enum PlanTier: String, CaseIterable, Codable {
    case pro = "Pro"
    case max5x = "Max 5x"
    case max20x = "Max 20x"

    /// Estimated 5-hour rolling window effective token limit
    var fiveHourLimit: Int {
        switch self {
        case .pro: return 5_000_000
        case .max5x: return 25_000_000
        case .max20x: return 100_000_000
        }
    }

    /// Estimated 7-day rolling window effective token limit (all models)
    var sevenDayLimit: Int {
        switch self {
        case .pro: return 25_000_000
        case .max5x: return 125_000_000
        case .max20x: return 500_000_000
        }
    }

    /// Estimated 7-day Sonnet-only limit
    var sevenDaySonnetLimit: Int {
        switch self {
        case .pro: return 50_000_000
        case .max5x: return 250_000_000
        case .max20x: return 1_000_000_000
        }
    }

    /// Detect plan tier from Keychain credentials
    static func detectFromKeychain() -> PlanTier? {
        guard let data = Self.readKeychainCredentials(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let tierString = oauth["rateLimitTier"] as? String else {
            return nil
        }

        if tierString.contains("20x") { return .max20x }
        if tierString.contains("5x") || tierString.contains("max") { return .max5x }
        return .pro
    }

    /// Read subscription type from Keychain
    static func subscriptionType() -> String? {
        guard let data = readKeychainCredentials(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else {
            return nil
        }
        return oauth["subscriptionType"] as? String
    }

    private static func readKeychainCredentials() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }
}
