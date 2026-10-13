import Foundation

extension MonthReport {
    /// Fetches everything needed for the current month in parallel and builds the report.
    /// `data-freshness` is optional; the other endpoints are required.
    public static func load(client: APIClient, today: Date = Date(), calendar: Calendar = .current) async throws -> MonthReport {
        let start = APIDates.dayString(monthStart(of: today, calendar: calendar), calendar: calendar)
        let end = APIDates.dayString(today, calendar: calendar)
        async let me = client.me()
        async let glance = client.monthGlance()
        async let daily = client.daily(start: start, end: end)
        async let byModel = client.byModel(start: start, end: end)
        async let freshness = try? client.dataFreshness()
        return try await build(me: me, glance: glance, daily: daily, byModel: byModel,
                               freshness: freshness, today: today, calendar: calendar)
    }
}
