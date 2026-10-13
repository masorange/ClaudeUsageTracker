import XCTest
@testable import UsageCore

final class ReportCacheTests: XCTestCase {
    private var cache: ReportCache!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cache = ReportCache(fileURL: directory.appendingPathComponent("report.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func report() throws -> MonthReport {
        MonthReport.build(me: try Fixture.decode("me"), glance: try Fixture.decode("month-glance"),
                          daily: try Fixture.decode("daily"), byModel: try Fixture.decode("by-model"),
                          freshness: try Fixture.decode("data-freshness"), today: TestCalendar.date(2026, 10, 13),
                          calendar: TestCalendar.madrid, now: TestCalendar.date(2026, 10, 13, 11))
    }

    func testRoundTripsReportForSameMonth() throws {
        let original = try report()
        cache.save(original)
        XCTAssertEqual(cache.load(today: TestCalendar.date(2026, 10, 20), calendar: TestCalendar.madrid), original)
    }

    func testDropsReportFromPreviousMonth() throws {
        cache.save(try report())
        XCTAssertNil(cache.load(today: TestCalendar.date(2026, 11, 1, 0, 1), calendar: TestCalendar.madrid))
    }

    func testClearRemovesFile() throws {
        cache.save(try report())
        cache.clear()
        XCTAssertNil(cache.load(today: TestCalendar.date(2026, 10, 13), calendar: TestCalendar.madrid))
    }

    func testMissingFileLoadsNil() {
        XCTAssertNil(cache.load(today: Date(), calendar: .current))
    }
}
