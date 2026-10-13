import XCTest
@testable import UsageCore

final class DecodingTests: XCTestCase {
    func testDecodesMe() throws {
        let me: Me = try Fixture.decode("me")
        XCTAssertEqual(me.teams, ["Bronze"])
        let litellm = try XCTUnwrap(me.budget(for: "litellm"))
        XCTAssertEqual(litellm.maxBudget, 205)
        XCTAssertEqual(litellm.budgetTeam, "Bronze")
        XCTAssertEqual(litellm.budgetResetAt, "2026-11-01 00:00:00")
        XCTAssertEqual(me.budget(for: "claude_enterprise")?.maxBudget, 1)
    }

    func testDecodesMonthGlance() throws {
        let glance: MonthGlance = try Fixture.decode("month-glance")
        let litellm = try XCTUnwrap(glance.provider("litellm"))
        XCTAssertEqual(litellm.spendMtd, 10.5261903, accuracy: 1e-9)
        XCTAssertEqual(litellm.projection ?? 0, 34.210118475, accuracy: 1e-9)
        XCTAssertEqual(litellm.maxBudget, 205)
    }

    func testDecodesDaily() throws {
        let daily: [DailySpend] = try Fixture.decode("daily")
        XCTAssertEqual(daily.count, 8)
        XCTAssertEqual(daily[1].day, "2026-10-02")
        XCTAssertEqual(daily[1].tokens, 8_969_255)
        XCTAssertEqual(daily[1].listSpend ?? 0, 8.3970301, accuracy: 1e-9)
    }

    func testDecodesByModel() throws {
        let rows: [ModelSpend] = try Fixture.decode("by-model")
        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows[0].model, "vertex_ai/claude-sonnet-5-5")
        XCTAssertEqual(rows[0].requests, 47)
    }

    func testDecodesFreshness() throws {
        let freshness: DataFreshness = try Fixture.decode("data-freshness")
        XCTAssertEqual(freshness.lastUpdated, "2026-10-13T08:30:15.530333+00:00")
    }

    func testIgnoresUnknownFieldsAndMissingOptionals() throws {
        let json = Data(#"{"provider":"litellm","spend_mtd":1.5,"brand_new_field":true}"#.utf8)
        let glance = try JSONDecoder.api.decode(ProviderGlance.self, from: json)
        XCTAssertEqual(glance.spendMtd, 1.5)
        XCTAssertNil(glance.maxBudget)
        XCTAssertNil(glance.projection)
    }
}
