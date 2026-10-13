import AppKit
import os
import UsageCore
import WebKit

/// Owns the persistent WebKit session used to sign in through Google IAP and to renew the IAP cookie silently.
@MainActor
final class IAPSession: NSObject, SessionStore {
    static let homeURL = URL(string: "https://ai-platform.cloud.masorange.es/")!
    /// Google sign-in rejects some embedded-browser user agents; this one is known to work with WKWebView.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36"
    private static let renewTimeout: TimeInterval = 20
    private static let idleOnLoginPage: TimeInterval = 5
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed,
    ]

    private let dataStore = WKWebsiteDataStore.default()
    private let logger = Logger(subsystem: "com.claudeusage.tracker", category: "auth")
    private lazy var gate = RenewalGate { [unowned self] in await self.performRenew() }
    private var loginWindow: LoginWindowController? {
        didSet { gate.interactiveLoginActive = loginWindow != nil }
    }

    func authCookie() async -> String? {
        let cookies = await dataStore.httpCookieStore.allCookies()
        let host = Self.homeURL.host ?? ""
        return cookies.first { $0.name == APIClient.cookieName && host.hasSuffix($0.domain.trimmingCharacters(in: ["."])) }?.value
    }

    func renew() async -> RenewResult {
        await gate.renew()
    }

    func presentLogin(title: String, onSuccess: @escaping () -> Void) {
        if let loginWindow {
            loginWindow.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LoginWindowController(session: self, title: title, onSuccess: { [weak self] in
            self?.loginWindow = nil
            onSuccess()
        }, onClose: { [weak self] in
            self?.loginWindow = nil
        })
        loginWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func signOut() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func makeWebView(frame: NSRect) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        return webView
    }

    private func performRenew() async -> RenewResult {
        let previousCookie = await authCookie()
        let webView = makeWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
        let tracker = NavigationTracker()
        webView.navigationDelegate = tracker
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        webView.load(URLRequest(url: Self.homeURL))

        let deadline = Date().addingTimeInterval(Self.renewTimeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
            // A hidden flow would invalidate the user's interactive sign-in (IAP keeps per-flow cookies).
            if gate.interactiveLoginActive {
                logger.info("Silent renewal abandoned: interactive sign-in started")
                return .needsLogin
            }
            // IAP only issues a new cookie after a successful round trip through Google.
            if let cookie = await authCookie(), cookie != previousCookie {
                logger.info("IAP session renewed silently")
                return .renewed
            }
            if let error = tracker.networkError, Self.offlineCodes.contains(error.code) {
                logger.info("Silent renewal failed: network unreachable (\(error.code.rawValue))")
                return .offline
            }
            guard let finished = tracker.lastFinishedURL, let finishedAt = tracker.lastFinishedAt else { continue }
            if finished.host != Self.homeURL.host, !webView.isLoading,
               Date().timeIntervalSince(finishedAt) > Self.idleOnLoginPage {
                logger.info("Silent renewal stopped at \(finished.host ?? "?", privacy: .public); sign-in required")
                return .needsLogin
            }
        }
        logger.info("Silent renewal timed out")
        return .needsLogin
    }
}
