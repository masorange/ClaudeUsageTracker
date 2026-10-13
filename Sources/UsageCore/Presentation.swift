import Foundation

/// Colour band of the budget progress bar.
public enum BudgetLevel: Equatable, Sendable {
    case ok, warning, critical

    public init(fraction: Double) {
        switch fraction {
        case ..<0.75: self = .ok
        case ..<0.9: self = .warning
        default: self = .critical
        }
    }
}

public enum TierMedal {
    private static let medals = ["iron": "🪨", "bronze": "🥉", "silver": "🥈", "gold": "🥇"]

    /// Emoji for a LiteLLM team tier, nil for unknown tiers.
    public static func medal(for tier: String) -> String? {
        medals[tier.lowercased()]
    }
}
