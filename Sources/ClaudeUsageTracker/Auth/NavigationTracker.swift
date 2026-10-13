import WebKit

/// Records the last main-frame navigation that finished in a web view.
@MainActor
final class NavigationTracker: NSObject, WKNavigationDelegate {
    private(set) var lastFinishedURL: URL?
    private(set) var lastFinishedAt: Date?
    var onFinish: ((URL?) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        record(webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        record(webView.url)
    }

    private func record(_ url: URL?) {
        lastFinishedURL = url
        lastFinishedAt = Date()
        onFinish?(url)
    }
}
