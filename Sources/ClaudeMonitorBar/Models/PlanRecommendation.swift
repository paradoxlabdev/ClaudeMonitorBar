import SwiftUI

struct PlanRecommendation {
    enum Action {
        case downgrade(to: String, price: String)
        case stay
        case upgrade(to: String, price: String)
    }

    let action: Action
    let reason: String
    let icon: String
    let color: Color

    static let prices: [(tier: String, label: String, price: Int, multiplier: Int)] = [
        ("pro",    "Pro",      20,  1),
        ("max5x",  "Max 5x",  100,  5),
        ("max20x", "Max 20x", 200, 20),
    ]

    static func recommend(
        currentPlan: String?,
        sevenDayUtil: Double,
        sevenDayReset: Int,
        fiveHourUtil: Double,
        fiveHourReset: Int
    ) -> PlanRecommendation {
        let plan = currentPlan?.lowercased() ?? ""
        let currentTierIndex: Int
        if plan.contains("20x") {
            currentTierIndex = 2
        } else if plan.contains("5x") || plan.contains("max") {
            currentTierIndex = 1
        } else {
            currentTierIndex = 0
        }

        let current = prices[currentTierIndex]
        let now = Date().timeIntervalSince1970

        // --- 7-day window ---
        let hoursUntil7d = max(0, (Double(sevenDayReset) - now) / 3600)
        let daysElapsed = max(0.25, 7.0 - hoursUntil7d / 24.0)
        let burnPerDay = sevenDayUtil / daysElapsed
        let projected7d = min(burnPerDay * 7.0, 2.0)

        // Blend actual + projected (more data = trust actual more)
        let conf7d = min(daysElapsed / 7.0, 1.0)
        let eff7d = sevenDayUtil * conf7d + projected7d * (1.0 - conf7d)

        let daysStr = String(format: "%.0f", daysElapsed)

        // --- Downgrade? ---
        if currentTierIndex > 0 {
            let cheaper = prices[currentTierIndex - 1]
            let ratio = Double(current.multiplier) / Double(cheaper.multiplier)
            let onCheaper = eff7d * ratio

            if onCheaper < 0.60 {
                let saving = current.price - cheaper.price
                return PlanRecommendation(
                    action: .downgrade(to: cheaper.label, price: "$\(cheaper.price)/mo"),
                    reason: "On \(cheaper.label) you'd use ~\(Int(onCheaper * 100))% of weekly limit (based on \(daysStr) days). Save $\(saving)/mo.",
                    icon: "arrow.down.circle.fill",
                    color: .green
                )
            }
        }

        // --- Upgrade? (based on 7-day utilization only) ---
        if currentTierIndex < prices.count - 1 && eff7d > 0.75 {
            let higher = prices[currentTierIndex + 1]
            let ratio = Double(current.multiplier) / Double(higher.multiplier)
            let onHigher = eff7d * ratio

            return PlanRecommendation(
                action: .upgrade(to: higher.label, price: "$\(higher.price)/mo"),
                reason: "Projected ~\(Int(eff7d * 100))% weekly usage (based on \(daysStr) days). On \(higher.label) it would be ~\(Int(onHigher * 100))%.",
                icon: "arrow.up.circle.fill",
                color: .orange
            )
        }

        // --- Stay ---
        return PlanRecommendation(
            action: .stay,
            reason: "Projected ~\(Int(eff7d * 100))% weekly usage (based on \(daysStr) days). Plan fits your usage well.",
            icon: "checkmark.circle.fill",
            color: .green
        )
    }
}
