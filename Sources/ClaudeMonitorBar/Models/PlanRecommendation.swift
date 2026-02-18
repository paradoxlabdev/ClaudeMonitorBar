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

        // How many days have elapsed in the 7-day window
        let hoursUntil7d = max(0, (Double(sevenDayReset) - now) / 3600)
        let daysElapsed = max(1.0, 7.0 - hoursUntil7d / 24.0)

        // Simple linear projection: if you keep this pace, where will you end up?
        let projected = min(sevenDayUtil / daysElapsed * 7.0, 2.0)

        let daysInt = Int(daysElapsed.rounded())
        let daysStr = daysInt == 1 ? "1 day" : "\(daysInt) days"
        let projectedPct = Int(projected * 100)

        // --- Downgrade? ---
        if currentTierIndex > 0 {
            let cheaper = prices[currentTierIndex - 1]
            let ratio = Double(current.multiplier) / Double(cheaper.multiplier)
            let onCheaper = projected * ratio

            if onCheaper < 0.60 {
                let saving = current.price - cheaper.price
                return PlanRecommendation(
                    action: .downgrade(to: cheaper.label, price: "$\(cheaper.price)/mo"),
                    reason: "Projected \(projectedPct)% by end of week (based on \(daysStr)). On \(cheaper.label) it would be ~\(Int(onCheaper * 100))%. Save $\(saving)/mo.",
                    icon: "arrow.down.circle.fill",
                    color: .green
                )
            }
        }

        // --- Upgrade? (based on 7-day projection only) ---
        if currentTierIndex < prices.count - 1 && projected > 0.75 {
            let higher = prices[currentTierIndex + 1]
            let ratio = Double(current.multiplier) / Double(higher.multiplier)
            let onHigher = projected * ratio

            return PlanRecommendation(
                action: .upgrade(to: higher.label, price: "$\(higher.price)/mo"),
                reason: "Projected \(projectedPct)% by end of week (based on \(daysStr)). On \(higher.label) it would be ~\(Int(onHigher * 100))%.",
                icon: "arrow.up.circle.fill",
                color: .orange
            )
        }

        // --- Stay ---
        return PlanRecommendation(
            action: .stay,
            reason: "Projected \(projectedPct)% by end of week (based on \(daysStr)).",
            icon: "checkmark.circle.fill",
            color: .green
        )
    }
}
