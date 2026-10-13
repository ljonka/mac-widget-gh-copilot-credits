import Foundation

public enum CreditsError: LocalizedError {
    case invalidQuota
    case expiredQuota
    case cli(String)

    public var errorDescription: String? {
        switch self {
        case .invalidQuota: return "Keine gültigen, begrenzten Copilot-Credits verfügbar."
        case .expiredQuota: return "GitHub liefert noch den alten Abrechnungsmonat."
        case .cli(let message): return message
        }
    }
}

public struct Quota {
    public let remaining: Double
    public let entitlement: Double
    public let reset: Date

    public static func decode(_ data: Data) throws -> Quota {
        struct Response: Decodable {
            struct Snapshot: Decodable {
                let entitlement: Double
                let remaining: Double?
                let quota_remaining: Double?
                let unlimited: Bool
            }
            let quota_reset_date: String?
            let quota_reset_date_utc: String?
            let quota_snapshots: [String: Snapshot]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let snapshot = response.quota_snapshots["premium_interactions"],
              !snapshot.unlimited, snapshot.entitlement > 0,
              let remaining = snapshot.quota_remaining ?? snapshot.remaining,
              remaining.isFinite, remaining >= 0,
              let resetString = response.quota_reset_date_utc ?? response.quota_reset_date else {
            throw CreditsError.invalidQuota
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var reset = formatter.date(from: resetString)
        if reset == nil {
            formatter.formatOptions = [.withInternetDateTime]
            reset = formatter.date(from: resetString.count == 10 ? resetString + "T00:00:00Z" : resetString)
        }
        guard let reset else { throw CreditsError.invalidQuota }
        return Quota(remaining: remaining, entitlement: snapshot.entitlement, reset: reset)
    }
}

public enum BudgetTone { case green, yellow, red }

public struct MonthlyBudget {
    public let remaining: Double
    public let entitlement: Double
    public let reset: Date
    public var usedThisPeriod: Double { max(0, entitlement - remaining) }
    public let totalDays: Int
    public let elapsedDays: Int
    public var percent: Double { usedThisPeriod / entitlement * 100 }
    public var idealDaily: Double { entitlement / Double(totalDays) }
    public var actualDaily: Double { usedThisPeriod / Double(elapsedDays) }
    public var projectedUsage: Double { actualDaily * Double(totalDays) }
    public var deviationPercent: Double {
        let deviation = (actualDaily / idealDaily - 1) * 100
        return abs(deviation) < 1e-9 ? 0 : deviation
    }
    public var fitsBudget: Bool { deviationPercent <= 0 }
    public var tone: BudgetTone { percent <= 50 ? .green : (percent < 80 ? .yellow : .red) }

    public static func calculate(_ quota: Quota, now: Date = Date()) throws -> MonthlyBudget {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let month = calendar.dateInterval(of: .month, for: now),
              quota.reset == month.end,
              let totalDays = calendar.range(of: .day, in: .month, for: now)?.count else {
            throw CreditsError.expiredQuota
        }
        return MonthlyBudget(remaining: quota.remaining, entitlement: quota.entitlement, reset: quota.reset,
                             totalDays: totalDays, elapsedDays: calendar.component(.day, from: now))
    }
}
