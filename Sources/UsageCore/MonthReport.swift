import Foundation

public struct DayUsage: Codable, Equatable, Sendable, Identifiable {
    public let day: Date
    public let tokens: Int
    public let spend: Double
    public var id: Date { day }
}

public struct ModelUsage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let spend: Double
    public let listSpend: Double
    public let requests: Int
    public let tokens: Int
    /// Number of models aggregated into this row; only set for the "others" row.
    public let groupedCount: Int?

    public var discount: Double? { MonthReport.discount(spend: spend, listSpend: listSpend) }
    public var isOthers: Bool { id == MonthReport.othersID }
}

/// Everything the dashboard shows for the current month (LiteLLM provider only).
public struct MonthReport: Codable, Equatable, Sendable {
    public static let provider = "litellm"
    public static let othersID = "others"
    public static let topModelCount = 5

    public let monthStart: Date
    public let generatedAt: Date
    public let dataUpdatedAt: Date?
    public let spend: Double
    public let tier: String?
    public let budget: Double?
    public let budgetResetAt: Date?
    public let projection: Double?
    public let days: [DayUsage]
    public let models: [ModelUsage]

    public var totalTokens: Int { days.reduce(0) { $0 + $1.tokens } }

    public var budgetFraction: Double? {
        guard let budget, budget > 0 else { return nil }
        return spend / budget
    }

    public var available: Double? { budget.map { max($0 - spend, 0) } }

    public var projectionFraction: Double? {
        guard let budget, budget > 0, let projection else { return nil }
        return projection / budget
    }

    /// Campaign discount in 0…1. Only reported when the list price exceeds the charged spend by more than 0.5 %,
    /// the same rule the AI Platform web uses.
    public static func discount(spend: Double, listSpend: Double) -> Double? {
        // Small epsilon so values exactly at the 1.005× boundary don't flip because of floating-point rounding.
        guard listSpend > 0, listSpend > spend * 1.005 + 1e-9 else { return nil }
        return 1 - spend / listSpend
    }

    public static func monthStart(of date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    public static func build(me: Me, glance: MonthGlance, daily: [DailySpend], byModel: [ModelSpend],
                             freshness: DataFreshness?, today: Date, calendar: Calendar,
                             now: Date = Date()) -> MonthReport {
        let monthStart = monthStart(of: today, calendar: calendar)
        let budget = me.budget(for: provider)
        let providerGlance = glance.provider(provider)
        return MonthReport(
            monthStart: monthStart,
            generatedAt: now,
            dataUpdatedAt: freshness?.lastUpdated.flatMap(APIDates.parseISO),
            spend: providerGlance?.spendMtd ?? daily.reduce(0) { $0 + $1.spend },
            tier: budget?.budgetTeam ?? me.teams?.first,
            budget: budget?.maxBudget,
            budgetResetAt: budget?.budgetResetAt.flatMap { APIDates.parseLocal($0, calendar: calendar) },
            projection: providerGlance?.projection,
            days: fillDays(daily, from: monthStart, through: today, calendar: calendar),
            models: rankModels(byModel)
        )
    }

    /// One entry per calendar day from `start` through `end`; days missing from the API count as zero.
    static func fillDays(_ daily: [DailySpend], from start: Date, through end: Date, calendar: Calendar) -> [DayUsage] {
        let byDay = Dictionary(daily.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [DayUsage] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            let entry = byDay[APIDates.dayString(day, calendar: calendar)]
            result.append(DayUsage(day: day, tokens: entry?.tokens ?? 0, spend: entry?.spend ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Most used models first (by tokens), merged by display name, MCP tool calls and empty rows removed.
    static func rankModels(_ rows: [ModelSpend]) -> [ModelUsage] {
        var merged: [String: ModelUsage] = [:]
        for row in rows where !row.model.hasPrefix("mcp:") {
            let listSpend = row.listSpend ?? row.spend
            guard row.tokens > 0 || row.spend > 0 || listSpend > 0 else { continue }
            let name = ModelNames.displayName(for: row.model)
            let previous = merged[name]
            merged[name] = ModelUsage(
                id: name,
                displayName: name,
                spend: (previous?.spend ?? 0) + row.spend,
                listSpend: (previous?.listSpend ?? 0) + listSpend,
                requests: (previous?.requests ?? 0) + row.requests,
                tokens: (previous?.tokens ?? 0) + row.tokens,
                groupedCount: nil
            )
        }
        let sorted = merged.values.sorted {
            ($0.tokens, $0.spend, $0.listSpend, $1.displayName) > ($1.tokens, $1.spend, $1.listSpend, $0.displayName)
        }
        guard sorted.count > topModelCount + 1 else { return sorted }
        let rest = sorted.dropFirst(topModelCount)
        let others = ModelUsage(
            id: othersID,
            displayName: othersID,
            spend: rest.reduce(0) { $0 + $1.spend },
            listSpend: rest.reduce(0) { $0 + $1.listSpend },
            requests: rest.reduce(0) { $0 + $1.requests },
            tokens: rest.reduce(0) { $0 + $1.tokens },
            groupedCount: rest.count
        )
        return Array(sorted.prefix(topModelCount)) + [others]
    }
}
