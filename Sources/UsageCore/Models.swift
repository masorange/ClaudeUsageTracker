import Foundation

/// Profile returned by `GET /me`. Only the fields the app uses are decoded.
public struct Me: Decodable, Equatable, Sendable {
    public let name: String?
    public let teams: [String]?
    public let budgets: [Budget]?

    public func budget(for provider: String) -> Budget? {
        budgets?.first { $0.provider == provider }
    }
}

public struct Budget: Decodable, Equatable, Sendable {
    public let provider: String
    public let maxBudget: Double?
    public let budgetTeam: String?
    public let budgetDuration: String?
    public let budgetResetAt: String?
}

/// Month-to-date overview returned by `GET /me/month-glance`.
public struct MonthGlance: Decodable, Equatable, Sendable {
    public let spendMtd: Double?
    public let projection: Double?
    public let projectionPct: Double?
    public let daysRemaining: Int?
    public let byProvider: [ProviderGlance]?

    public func provider(_ name: String) -> ProviderGlance? {
        byProvider?.first { $0.provider == name }
    }
}

public struct ProviderGlance: Decodable, Equatable, Sendable {
    public let provider: String
    public let spendMtd: Double
    public let maxBudget: Double?
    public let projection: Double?
    public let projectionPct: Double?
}

/// One row of `GET /spend/daily`. Days without activity are not returned by the API.
public struct DailySpend: Decodable, Equatable, Sendable {
    public let day: String
    public let spend: Double
    public let listSpend: Double?
    public let requests: Int
    public let tokens: Int
}

/// One row of `GET /spend/by-model`. MCP tool calls appear as `mcp: <tool>`.
public struct ModelSpend: Decodable, Equatable, Sendable {
    public let model: String
    public let spend: Double
    public let listSpend: Double?
    public let requests: Int
    public let tokens: Int
}

public struct DataFreshness: Decodable, Equatable, Sendable {
    public let lastUpdated: String?
}

extension JSONDecoder {
    /// Decoder matching the API's snake_case JSON.
    public static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
