import Foundation

/// Date helpers for the formats used by the AI Platform API.
public enum APIDates {
    /// `YYYY-MM-DD` for `date` in the calendar's time zone.
    public static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses `YYYY-MM-DD` or `YYYY-MM-DD HH:mm:ss[.ffffff]` as a local date in `calendar`.
    public static func parseLocal(_ string: String, calendar: Calendar) -> Date? {
        let dateParts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard dateParts.count == 3 else { return nil }
        var components = DateComponents(year: dateParts[0], month: dateParts[1], day: dateParts[2])
        let timeParts = string.dropFirst(11).split(separator: ".").first?
            .split(separator: ":").compactMap { Int($0) } ?? []
        if timeParts.count == 3 {
            components.hour = timeParts[0]
            components.minute = timeParts[1]
            components.second = timeParts[2]
        }
        return calendar.date(from: components)
    }

    /// Parses ISO-8601 timestamps with any number of fractional-second digits.
    public static func parseISO(_ string: String) -> Date? {
        let withoutFraction = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: withoutFraction)
    }
}
