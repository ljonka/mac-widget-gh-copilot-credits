import XCTest
@testable import CreditsCore

final class BudgetTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func quota(_ remaining: Double = 190, reset: String = "2026-11-01", entitlement: Double = 300) throws -> Quota {
        try Quota.decode(Data("""
        {"quota_reset_date":"\(reset)","quota_snapshots":{"premium_interactions":{
        "entitlement":\(entitlement),"quota_remaining":\(remaining),"remaining":189,"unlimited":false}}}
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

    func testMonthlyUsageIsKnownImmediatelyWithoutBaseline() throws {
        let result = try MonthlyBudget.calculate(quota(190.5), now: date("2026-10-13T19:00:00Z"))
        XCTAssertEqual(result.usedThisPeriod, 109.5)
        XCTAssertEqual(result.entitlement, 300)
        XCTAssertEqual(result.percent, 36.5)
        XCTAssertEqual(result.reset, date("2026-11-01T00:00:00Z"))
        XCTAssertEqual(result.totalDays, 31)
        XCTAssertEqual(result.elapsedDays, 13)
    }

    func testExactEvenDistributionLandsOnMonthlyBudget() throws {
        let result = try MonthlyBudget.calculate(quota(180, entitlement: 310), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.idealDaily, 10)
        XCTAssertEqual(result.actualDaily, 10)
        XCTAssertEqual(result.deviationPercent, 0)
        XCTAssertEqual(result.projectedUsage, 310)
        XCTAssertTrue(result.fitsBudget)
    }

    func testOverAverageProjectsOverspending() throws {
        let result = try MonthlyBudget.calculate(quota(154, entitlement: 310), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.actualDaily, 12)
        XCTAssertEqual(result.deviationPercent, 20, accuracy: 0.0001)
        XCTAssertEqual(result.projectedUsage, 372)
        XCTAssertFalse(result.fitsBudget)
    }

    func testUnderAverageProjectsRemainingCredits() throws {
        let result = try MonthlyBudget.calculate(quota(206, entitlement: 310), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.actualDaily, 8)
        XCTAssertEqual(result.deviationPercent, -20, accuracy: 0.0001)
        XCTAssertEqual(result.projectedUsage, 248)
        XCTAssertTrue(result.fitsBudget)
    }

    func testFractionalPointLandingIsNotAnOvershootDueToRounding() throws {
        let result = try MonthlyBudget.calculate(quota(300 - 300.0 / 31 * 13), now: date("2026-10-13T12:00:00Z"))
        XCTAssertEqual(result.deviationPercent, 0)
        XCTAssertTrue(result.fitsBudget)
    }

    func testColorBoundariesAndOverBudget() throws {
        for (remaining, percent, tone) in [(150.0, 50.0, BudgetTone.green),
                                          (147.0, 51.0, .yellow),
                                          (63.0, 79.0, .yellow),
                                          (60.0, 80.0, .red),
                                          (0.0, 100.0, .red)] {
            let result = try MonthlyBudget.calculate(quota(remaining), now: date("2026-10-13T12:00:00Z"))
            XCTAssertEqual(result.percent, percent, accuracy: 0.0001)
            XCTAssertEqual(result.tone, tone)
        }
    }

    func testUTCDayChangeUpdatesAverage() throws {
        let before = try MonthlyBudget.calculate(quota(180, entitlement: 310), now: date("2026-10-13T23:59:59Z"))
        let after = try MonthlyBudget.calculate(quota(180, entitlement: 310), now: date("2026-10-14T00:00:00Z"))
        XCTAssertEqual(before.elapsedDays, 13)
        XCTAssertEqual(after.elapsedDays, 14)
        XCTAssertEqual(before.actualDaily, 10)
        XCTAssertEqual(after.actualDaily, 130.0 / 14, accuracy: 0.0001)
    }

    func testLastDayAndLeapYear() throws {
        let last = try MonthlyBudget.calculate(quota(0), now: date("2026-10-31T23:59:59Z"))
        XCTAssertEqual(last.elapsedDays, 31)
        XCTAssertEqual(last.deviationPercent, 0)
        XCTAssertTrue(last.fitsBudget)
        let leap = try MonthlyBudget.calculate(quota(20, reset: "2028-03-01"), now: date("2028-02-28T12:00:00Z"))
        XCTAssertEqual(leap.totalDays, 29)
        XCTAssertEqual(leap.elapsedDays, 28)
    }

    func testFirstDayWithNoUsageHasNoDivisionByZero() throws {
        let result = try MonthlyBudget.calculate(quota(300), now: date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(result.elapsedDays, 1)
        XCTAssertEqual(result.actualDaily, 0)
        XCTAssertEqual(result.percent, 0)
        XCTAssertEqual(result.deviationPercent, -100)
        XCTAssertEqual(result.projectedUsage, 0)
        XCTAssertTrue(result.fitsBudget)
    }

    func testExpiredOrWrongMonthQuotaIsRejected() throws {
        XCTAssertThrowsError(try MonthlyBudget.calculate(quota(), now: date("2026-11-01T00:00:00Z")))
        XCTAssertThrowsError(try MonthlyBudget.calculate(quota(reset: "2026-12-01"), now: date("2026-10-13T12:00:00Z")))
    }

    func testNewMonthUsesNewMonthLengthAndAllowance() throws {
        let result = try MonthlyBudget.calculate(quota(300, reset: "2026-12-01"), now: date("2026-11-01T00:00:00Z"))
        XCTAssertEqual(result.totalDays, 30)
        XCTAssertEqual(result.elapsedDays, 1)
        XCTAssertEqual(result.idealDaily, 10)
        XCTAssertEqual(result.usedThisPeriod, 0)
    }
}
