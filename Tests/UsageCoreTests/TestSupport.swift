import Foundation
import XCTest
@testable import UsageCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder.api.decode(T.self, from: data(name))
    }
}

enum TestCalendar {
    static var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        madrid.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
