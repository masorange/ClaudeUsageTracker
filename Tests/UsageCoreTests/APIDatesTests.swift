import XCTest
@testable import UsageCore

final class APIDatesTests: XCTestCase {
    func testParsesISOWithMicroseconds() throws {
        let date = try XCTUnwrap(APIDates.parseISO("2026-10-13T08:30:15.530333+00:00"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(parts, DateComponents(year: 2026, month: 10, day: 13, hour: 8, minute: 30, second: 15))
    }

    func testParsesLocalTimestampAndDate() {
        let expected = TestCalendar.date(2026, 11, 1, 0)
        XCTAssertEqual(APIDates.parseLocal("2026-11-01 00:00:00", calendar: TestCalendar.madrid), expected)
        XCTAssertEqual(APIDates.parseLocal("2026-11-01", calendar: TestCalendar.madrid), expected)
        XCTAssertNil(APIDates.parseLocal("garbage", calendar: TestCalendar.madrid))
    }

    func testDayStringUsesLocalCalendar() {
        // 23:30 in Madrid is still the 13th locally (21:30 UTC).
        XCTAssertEqual(APIDates.dayString(TestCalendar.date(2026, 10, 13, 23, 30), calendar: TestCalendar.madrid), "2026-10-13")
        XCTAssertEqual(APIDates.dayString(TestCalendar.date(2026, 10, 3), calendar: TestCalendar.madrid), "2026-10-03")
    }
}
