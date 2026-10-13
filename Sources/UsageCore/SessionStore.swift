import Foundation

/// Source of the Google IAP session cookie that authenticates API calls.
public protocol SessionStore: AnyObject, Sendable {
    /// Current IAP cookie value, nil if there is none.
    func authCookie() async -> String?

    /// Tries to obtain a fresh cookie without user interaction.
    /// Returns false when an interactive sign-in is required.
    func renew() async -> Bool
}
