import XCTest
@testable import UsageCore

final class MonthReportTests: XCTestCase {
    private func fixtureReport(today: Date = TestCalendar.date(2026, 10, 13)) throws -> MonthReport {
        MonthReport.build(
            me: try Fixture.decode("me"),
            glance: try Fixture.decode("month-glance"),
            daily: try Fixture.decode("daily"),
            byModel: try Fixture.decode("by-model"),
            freshness: try Fixture.decode("data-freshness"),
            today: today,
            calendar: TestCalendar.madrid,
            now: TestCalendar.date(2026, 10, 13, 11)
        )
    }

    private func row(_ model: String, spend: Double = 0, list: Double? = nil, requests: Int = 1, tokens: Int) -> ModelSpend {
        ModelSpend(model: model, spend: spend, listSpend: list, requests: requests, tokens: tokens)
    }

    func testSpendTierAndBudget() throws {
        let report = try fixtureReport()
        XCTAssertEqual(report.spend, 10.5261903, accuracy: 1e-9)
        XCTAssertEqual(report.tier, "Bronze")
        XCTAssertEqual(report.budget, 205)
        XCTAssertEqual(report.projection ?? 0, 34.210118475, accuracy: 1e-9)
        XCTAssertEqual(report.budgetResetAt, TestCalendar.date(2026, 11, 1, 0))
        XCTAssertEqual(report.budgetFraction ?? 0, 0.05134726975609756, accuracy: 1e-12)
        XCTAssertEqual(report.available ?? 0, 194.4738097, accuracy: 1e-9)
        XCTAssertEqual(report.monthStart, TestCalendar.date(2026, 10, 1, 0))
        XCTAssertNotNil(report.dataUpdatedAt)
    }

    func testFillsEveryDayUpToToday() throws {
        let report = try fixtureReport()
        XCTAssertEqual(report.days.count, 13)
        XCTAssertEqual(report.days.first?.day, TestCalendar.date(2026, 10, 1, 0))
        XCTAssertEqual(report.days[1].tokens, 8_969_255)
        XCTAssertEqual(report.days[2].tokens, 0) // Oct 3 has no activity
        XCTAssertEqual(report.days[12].tokens, 0) // Oct 13
        XCTAssertEqual(report.totalTokens, 144_579_390)
    }

    func testRanksByUsageMergesSameNameAndExcludesMcp() throws {
        let report = try fixtureReport()
        XCTAssertEqual(report.models.map(\.displayName), ["Opus 5.5", "Sonnet 5.5"])
        let opus = report.models[0]
        XCTAssertEqual(opus.spend, 0)
        XCTAssertEqual(opus.discount ?? 0, 1, accuracy: 1e-12)
        let sonnet = report.models[1]
        XCTAssertEqual(sonnet.spend, 10.5261903, accuracy: 1e-9)
        XCTAssertEqual(sonnet.listSpend, 48.96019695, accuracy: 1e-6)
        XCTAssertEqual(sonnet.tokens, 69_097_175)
        XCTAssertEqual(sonnet.requests, 102)
        XCTAssertEqual(sonnet.discount ?? 0, 0.785005147941914, accuracy: 1e-9)
    }

    func testFallsBackToDailySumWithoutProviderGlance() throws {
        let glance = MonthGlance(spendMtd: nil, projection: nil, projectionPct: nil, daysRemaining: nil, byProvider: nil)
        let report = MonthReport.build(
            me: try Fixture.decode("me"), glance: glance, daily: try Fixture.decode("daily"),
            byModel: [], freshness: nil, today: TestCalendar.date(2026, 10, 13), calendar: TestCalendar.madrid)
        XCTAssertEqual(report.spend, 10.5261903, accuracy: 1e-9)
        XCTAssertNil(report.projection)
        XCTAssertNil(report.dataUpdatedAt)
    }

    func testTierFallsBackToTeamsWithoutBudget() {
        let me = Me(name: nil, teams: ["Gold"], budgets: nil)
        let glance = MonthGlance(spendMtd: nil, projection: nil, projectionPct: nil, daysRemaining: nil, byProvider: nil)
        let report = MonthReport.build(me: me, glance: glance, daily: [], byModel: [], freshness: nil,
                                       today: TestCalendar.date(2026, 10, 5), calendar: TestCalendar.madrid)
        XCTAssertEqual(report.tier, "Gold")
        XCTAssertNil(report.budget)
        XCTAssertNil(report.budgetFraction)
        XCTAssertNil(report.available)
    }

    func testGroupsTwoOrMoreLeftoversIntoOthers() {
        let rows = (1...7).map { row("anthropic/claude-opus-\($0)", spend: Double($0), tokens: 100 * $0) }
        let models = MonthReport.rankModels(rows)
        XCTAssertEqual(models.count, 6)
        XCTAssertEqual(models.first?.displayName, "Opus 7")
        let others = try! XCTUnwrap(models.last)
        XCTAssertTrue(others.isOthers)
        XCTAssertEqual(others.groupedCount, 2)
        XCTAssertEqual(others.tokens, 300)
        XCTAssertEqual(others.spend, 3)
    }

    func testSingleLeftoverIsShownAsNormalRow() {
        let rows = (1...6).map { row("anthropic/claude-opus-\($0)", tokens: 100 * $0) }
        let models = MonthReport.rankModels(rows)
        XCTAssertEqual(models.count, 6)
        XCTAssertFalse(models.contains { $0.isOthers })
    }

    func testDropsEmptyRows() {
        let models = MonthReport.rankModels([row("anthropic/claude-opus-5", tokens: 0), row("mcp: x", tokens: 0)])
        XCTAssertTrue(models.isEmpty)
    }

    func testDiscountThreshold() {
        XCTAssertNil(MonthReport.discount(spend: 100, listSpend: 100.5))
        XCTAssertEqual(MonthReport.discount(spend: 100, listSpend: 100.6) ?? 0, 0.005964214711729587, accuracy: 1e-12)
        XCTAssertNil(MonthReport.discount(spend: 0, listSpend: 0))
        XCTAssertEqual(MonthReport.discount(spend: 0, listSpend: 10), 1)
    }

    func testFirstDayOfMonthWithoutUsage() {
        let me = Me(name: nil, teams: nil, budgets: nil)
        let glance = MonthGlance(spendMtd: 0, projection: nil, projectionPct: nil, daysRemaining: nil, byProvider: [])
        let report = MonthReport.build(me: me, glance: glance, daily: [], byModel: [], freshness: nil,
                                       today: TestCalendar.date(2026, 11, 1, 0, 5), calendar: TestCalendar.madrid)
        XCTAssertEqual(report.days.count, 1)
        XCTAssertEqual(report.days[0].tokens, 0)
        XCTAssertEqual(report.spend, 0)
        XCTAssertTrue(report.models.isEmpty)
    }

    func testIgnoresGlanceFromAnotherMonth() throws {
        // Server still reports October right after local midnight on Nov 1st.
        let json = Data(#"{"month_start":"2026-10-01","spend_mtd":180,"projection":190,"by_provider":[{"provider":"litellm","spend_mtd":180,"projection":190}]}"#.utf8)
        let glance = try JSONDecoder.api.decode(MonthGlance.self, from: json)
        let daily = [DailySpend(day: "2026-11-01", spend: 0.5, listSpend: 0.5, requests: 1, tokens: 10)]
        let report = MonthReport.build(me: Me(name: nil, teams: nil, budgets: nil), glance: glance, daily: daily,
                                       byModel: [], freshness: nil, today: TestCalendar.date(2026, 11, 1, 0, 30),
                                       calendar: TestCalendar.madrid)
        XCTAssertEqual(report.spend, 0.5)
        XCTAssertNil(report.projection)
    }

    func testIsCurrentOnlyForSameMonth() throws {
        let report = try fixtureReport()
        XCTAssertTrue(report.isCurrent(at: TestCalendar.date(2026, 10, 31, 23, 59), calendar: TestCalendar.madrid))
        XCTAssertFalse(report.isCurrent(at: TestCalendar.date(2026, 11, 1, 0, 1), calendar: TestCalendar.madrid))
    }
}
