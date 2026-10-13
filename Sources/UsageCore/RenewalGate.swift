import Foundation

/// Serialises silent IAP renewals.
///
/// IAP keeps per-flow state in cookies, so two sign-in flows sharing one cookie store invalidate each other.
/// The gate makes concurrent callers share one attempt and refuses to start a silent flow while the user is
/// signing in interactively.
@MainActor
public final class RenewalGate {
    public var interactiveLoginActive = false

    private let attempt: @MainActor () async -> RenewResult
    private var inFlight: Task<RenewResult, Never>?

    public init(attempt: @escaping @MainActor () async -> RenewResult) {
        self.attempt = attempt
    }

    public func renew() async -> RenewResult {
        if interactiveLoginActive { return .needsLogin }
        if let inFlight { return await inFlight.value }
        let task = Task { await attempt() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
