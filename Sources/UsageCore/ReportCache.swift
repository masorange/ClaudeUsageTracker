import Foundation

/// Persists the last successful report so the app shows data instantly on launch.
public struct ReportCache: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/ClaudeUsageTracker/report.json`
    public static var standard: ReportCache {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ReportCache(fileURL: support.appendingPathComponent("ClaudeUsageTracker/report.json"))
    }

    /// Cached report, or nil if there is none or it belongs to another month than `today`.
    public func load(today: Date = Date(), calendar: Calendar = .current) -> MonthReport? {
        guard let data = try? Data(contentsOf: fileURL),
              let report = try? JSONDecoder().decode(MonthReport.self, from: data) else { return nil }
        return report.monthStart == MonthReport.monthStart(of: today, calendar: calendar) ? report : nil
    }

    public func save(_ report: MonthReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
