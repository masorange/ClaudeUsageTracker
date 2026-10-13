import AppKit
import WebKit

/// Window with the AI Platform page; the user signs in with corporate SSO and the window closes itself.
@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate, WKHTTPCookieStoreObserver {
    private let session: IAPSession
    private let webView: WKWebView
    private let tracker = NavigationTracker()
    private let onSuccess: () -> Void
    private let onClose: () -> Void
    private var succeeded = false
    /// Cookie present before sign-in; success requires a different one (a stale session cookie may linger).
    private var previousCookie: String?

    init(session: IAPSession, title: String, onSuccess: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.onSuccess = onSuccess
        self.onClose = onClose
        let frame = NSRect(x: 0, y: 0, width: 520, height: 700)
        webView = session.makeWebView(frame: frame)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        tracker.onFinish = { [weak self] url in self?.checkSignedIn(url) }
        webView.navigationDelegate = tracker
        Task { @MainActor [weak self] in
            guard let self else { return }
            previousCookie = await session.authCookie()
            // Finish as soon as IAP sets a new session cookie, even if the last page never finishes loading.
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            webView.load(URLRequest(url: IAPSession.homeURL))
        }
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in self?.checkSignedIn(nil) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func checkSignedIn(_ url: URL?) {
        guard !succeeded else { return }
        Task { @MainActor in
            guard let cookie = await session.authCookie(), cookie != previousCookie, !succeeded else { return }
            succeeded = true
            window?.close()
            onSuccess()
        }
    }

    func windowWillClose(_ notification: Notification) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView.stopLoading()
        if !succeeded { onClose() }
    }
}
