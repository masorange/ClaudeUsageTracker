import Foundation

/// Outcome of a silent session renewal.
public enum RenewResult: Equatable, Sendable {
    case renewed
    case needsLogin
    case offline
}

/// Source of the Google IAP session cookie that authenticates API calls.
public protocol SessionStore: AnyObject, Sendable {
    /// Current IAP cookie value, nil if there is none.
    func authCookie() async -> String?

    /// Tries to obtain a fresh cookie without user interaction.
    /// `.needsLogin` means an interactive sign-in is required; `.offline` means the network is unreachable.
    func renew() async -> RenewResult
}
