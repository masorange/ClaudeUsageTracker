import XCTest
@testable import UsageCore

final class PresentationTests: XCTestCase {
    func testBudgetLevels() {
        XCTAssertEqual(BudgetLevel(fraction: 0), .ok)
        XCTAssertEqual(BudgetLevel(fraction: 0.749), .ok)
        XCTAssertEqual(BudgetLevel(fraction: 0.75), .warning)
        XCTAssertEqual(BudgetLevel(fraction: 0.899), .warning)
        XCTAssertEqual(BudgetLevel(fraction: 0.9), .critical)
        XCTAssertEqual(BudgetLevel(fraction: 1.4), .critical)
    }

    func testTierMedals() {
        XCTAssertEqual(TierMedal.medal(for: "Bronze"), "🥉")
        XCTAssertEqual(TierMedal.medal(for: "gold"), "🥇")
        XCTAssertEqual(TierMedal.medal(for: "Silver"), "🥈")
        XCTAssertEqual(TierMedal.medal(for: "Iron"), "🪨")
        XCTAssertNil(TierMedal.medal(for: "Platinum"))
    }
}
