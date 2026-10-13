import Foundation
import os
import UsageCore

/// Outcome of the last refresh.
enum LoadState: Equatable {
    case idle
    case ok
    case needsLogin
    case offline(String)
    case failed(String)
    case apiChanged
}

/// Loads and caches the monthly report and drives periodic refreshes.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var report: MonthReport?
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var lastSuccess: Date?

    private let session: IAPSession
    private let client: APIClient
    private let cache: ReportCache
    private let logger = Logger(subsystem: "com.claudeusage.tracker", category: "model")
    private var timer: Timer?
    /// A refresh requested while another one is running (e.g. right after sign-in) runs once it finishes.
    private var refreshQueued = false

    init(session: IAPSession, cache: ReportCache = .standard) {
        self.session = session
        self.cache = cache
        client = APIClient(store: session)
        if let cached = cache.load() {
            report = cached
            lastSuccess = cached.generatedAt
        }
    }

    func startAutoRefresh(minutes: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// Refreshes when the last successful load is older than `maxAge` seconds.
    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < maxAge, state == .ok,
           report?.isCurrent() == true { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else {
            refreshQueued = true
            return
        }
        isLoading = true
        await loadReport()
        dropReportFromPreviousMonth()
        isLoading = false
        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    private func loadReport() async {
        do {
            let fresh = try await MonthReport.load(client: client)
            report = fresh
            lastSuccess = fresh.generatedAt
            state = .ok
            cache.save(fresh)
        } catch APIError.needsLogin {
            state = .needsLogin
        } catch APIError.network(let message) {
            state = .offline(message)
        } catch APIError.decoding(let detail) {
            logger.error("Decoding failed: \(detail, privacy: .public)")
            state = .apiChanged
        } catch APIError.server(let status) {
            logger.error("Server error \(status)")
            state = .failed("HTTP \(status)")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func signIn(title: String) {
        session.presentLogin(title: title) { [weak self] in
            Task { await self?.refresh() }
        }
    }

    func signOut() async {
        await session.signOut()
        cache.clear()
        report = nil
        lastSuccess = nil
        state = .needsLogin
    }

    /// Around midnight on the 1st a load may finish with last month's data; discard it and load again.
    private func dropReportFromPreviousMonth() {
        guard let report, !report.isCurrent() else { return }
        self.report = nil
        state = .idle
        refreshQueued = true
    }
}
