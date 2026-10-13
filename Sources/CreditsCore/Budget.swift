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

public struct DailyBudget {
    public let remaining: Double
    public let entitlement: Double
    public let reset: Date
    public var usedThisPeriod: Double { max(0, entitlement - remaining) }
    public let days: Int
    public let dailyBudget: Double
    public let usedToday: Double
    public let percent: Double
    public var tone: BudgetTone { percent <= 50 ? .green : (percent < 80 ? .yellow : .red) }
}

public struct BudgetTracker: Codable {
    struct Baseline: Codable, Equatable {
        let day: Date
        let reset: Date
        let entitlement: Double
        let remaining: Double
        let days: Int
    }
    var baseline: Baseline?

    public init() {}

    public mutating func update(_ quota: Quota, now: Date = Date()) throws -> DailyBudget {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: now)
        let resetDay = calendar.startOfDay(for: quota.reset)
        let days = calendar.dateComponents([.day], from: day, to: resetDay).day ?? 0
        guard quota.reset > now, days > 0 else { throw CreditsError.expiredQuota }

        if baseline?.day != day || baseline?.reset != quota.reset ||
            baseline?.entitlement != quota.entitlement || quota.remaining > (baseline?.remaining ?? 0) {
            baseline = Baseline(day: day, reset: quota.reset, entitlement: quota.entitlement,
                                remaining: quota.remaining, days: days)
        }
        let baseline = baseline!
        let budget = baseline.remaining / Double(baseline.days)
        let used = max(0, baseline.remaining - quota.remaining)
        let percent = budget > 0 ? used / budget * 100 : 100
        return DailyBudget(remaining: quota.remaining, entitlement: quota.entitlement, reset: quota.reset,
                           days: days, dailyBudget: budget,
                           usedToday: used, percent: percent)
    }
}
