import XCTest
@testable import CreditsCore

final class BudgetTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func quota(_ remaining: Double = 190, reset: String = "2026-11-01") throws -> Quota {
        try Quota.decode(Data("""
        {"quota_reset_date":"\(reset)","quota_snapshots":{"premium_interactions":{
        "entitlement":300,"quota_remaining":\(remaining),"remaining":189,"unlimited":false}}}
        """.utf8))
    }

    func testUsesFractionalCreditsAndUTCReset() throws {
        let value = try quota(190.5)
        XCTAssertEqual(value.remaining, 190.5)
        XCTAssertEqual(value.reset, date("2026-11-01T00:00:00Z"))
    }

    func testFallsBackToIntegerRemaining() throws {
        let value = try Quota.decode(Data("""
        {"quota_reset_date_utc":"2026-11-01T00:00:00.000Z","quota_snapshots":{
        "premium_interactions":{"entitlement":300,"remaining":120,"unlimited":false}}}
        """.utf8))
        XCTAssertEqual(value.remaining, 120)
    }

    func testRejectsMissingUnlimitedAndInvalidQuota() {
        for json in ["{}", """
        {"quota_reset_date":"2026-11-01","quota_snapshots":{"premium_interactions":{
        "entitlement":0,"remaining":0,"unlimited":true}}}
        """, """
        {"quota_reset_date":"invalid","quota_snapshots":{"premium_interactions":{
        "entitlement":300,"remaining":120,"unlimited":false}}}
        """] {
            XCTAssertThrowsError(try Quota.decode(Data(json.utf8)))
        }
    }

    func testFirstReadingIncludesTodayInRemainingDays() throws {
        var tracker = BudgetTracker()
        let result = try tracker.update(quota(), now: date("2026-10-13T19:00:00Z"))
        XCTAssertEqual(result.days, 19)
        XCTAssertEqual(result.dailyBudget, 10)
        XCTAssertEqual(result.usedToday, 0)
        XCTAssertEqual(result.percent, 0)
    }

    func testMonthlyUsageEntitlementAndResetAreAvailableForDisplay() throws {
        var tracker = BudgetTracker()
        let result = try tracker.update(quota(190.5), now: date("2026-10-13T19:00:00Z"))
        XCTAssertEqual(result.usedThisPeriod, 109.5)
        XCTAssertEqual(result.entitlement, 300)
        XCTAssertEqual(result.reset, date("2026-11-01T00:00:00Z"))
    }

    func testBudgetStaysFixedThroughoutDay() throws {
        var tracker = BudgetTracker()
        _ = try tracker.update(quota(), now: date("2026-10-13T00:00:00Z"))
        let result = try tracker.update(quota(182), now: date("2026-10-13T18:00:00Z"))
        XCTAssertEqual(result.dailyBudget, 10)
        XCTAssertEqual(result.usedToday, 8)
        XCTAssertEqual(result.percent, 80)
        XCTAssertEqual(result.tone, .red)
    }

    func testColorBoundariesAndOverBudget() throws {
        for (remaining, percent, tone) in [(185.0, 50.0, BudgetTone.green),
                                          (184.9, 51.0, .yellow),
                                          (182.1, 79.0, .yellow),
                                          (182.0, 80.0, .red),
                                          (175.0, 150.0, .red)] {
            var tracker = BudgetTracker()
            _ = try tracker.update(quota(), now: date("2026-10-13T00:00:00Z"))
            let result = try tracker.update(quota(remaining), now: date("2026-10-13T12:00:00Z"))
            XCTAssertEqual(result.percent, percent, accuracy: 0.0001)
            XCTAssertEqual(result.tone, tone)
        }
    }

    func testNewUTCDayStartsNewBudget() throws {
        var tracker = BudgetTracker()
        _ = try tracker.update(quota(), now: date("2026-10-13T23:59:00Z"))
        let result = try tracker.update(quota(180), now: date("2026-10-14T00:00:00Z"))
        XCTAssertEqual(result.days, 18)
        XCTAssertEqual(result.dailyBudget, 10)
        XCTAssertEqual(result.usedToday, 0)
    }

    func testLastDayAndLeapYear() throws {
        var tracker = BudgetTracker()
        let last = try tracker.update(quota(20), now: date("2026-10-31T23:59:59Z"))
        XCTAssertEqual(last.days, 1)
        XCTAssertEqual(last.dailyBudget, 20)
        let leap = try tracker.update(quota(20, reset: "2028-03-01"), now: date("2028-02-28T12:00:00Z"))
        XCTAssertEqual(leap.days, 2)
    }

    func testExhaustedCreditsAreRedWithoutDivisionByZero() throws {
        var tracker = BudgetTracker()
        let result = try tracker.update(quota(0), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.dailyBudget, 0)
        XCTAssertEqual(result.percent, 100)
        XCTAssertEqual(result.tone, .red)
    }

    func testExpiredQuotaDoesNotOverwriteBaseline() throws {
        var tracker = BudgetTracker()
        _ = try tracker.update(quota(), now: date("2026-10-13T12:00:00Z"))
        let before = tracker.baseline
        XCTAssertThrowsError(try tracker.update(quota(), now: date("2026-11-01T00:00:00Z")))
        XCTAssertEqual(tracker.baseline, before)
    }

    func testRestartPreservesDailyUsage() throws {
        var tracker = BudgetTracker()
        _ = try tracker.update(quota(), now: date("2026-10-13T01:00:00Z"))
        let saved = try JSONEncoder().encode(tracker)
        var restored = try JSONDecoder().decode(BudgetTracker.self, from: saved)
        let result = try restored.update(quota(185), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.percent, 50)
    }

    func testQuotaIncreaseStartsFreshBaseline() throws {
        var tracker = BudgetTracker()
        _ = try tracker.update(quota(), now: date("2026-10-13T01:00:00Z"))
        let result = try tracker.update(quota(200), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.usedToday, 0)
        XCTAssertEqual(result.dailyBudget, 200.0 / 19, accuracy: 0.0001)
    }
}
