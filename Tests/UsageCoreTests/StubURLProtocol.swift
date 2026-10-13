import Foundation
@testable import UsageCore

/// Intercepts every request of a URLSession configured with it.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data("{}".utf8)
    }

    private static let lock = NSLock()
    private static var _handler: ((URLRequest) -> Reply)?
    private static var _error: URLError?
    private static var _requests: [URLRequest] = []

    static var handler: ((URLRequest) -> Reply)? {
        get { lock.sync { _handler } }
        set { lock.sync { _handler = newValue } }
    }
    static var error: URLError? {
        get { lock.sync { _error } }
        set { lock.sync { _error = newValue } }
    }
    static var requests: [URLRequest] { lock.sync { _requests } }

    static func reset() {
        lock.sync { _handler = nil; _error = nil; _requests = [] }
    }

    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.sync { Self._requests.append(request) }
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let reply = Self.handler?(request) ?? Reply()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension NSLock {
    /// `NSLocking.withLock` requires macOS 14; the package targets macOS 13.
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

final class FakeSessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cookie: String?
    private let renewResult: RenewResult
    private let cookieAfterRenew: String?
    private var _renewCalls = 0

    init(cookie: String?, renewResult: RenewResult = .needsLogin, cookieAfterRenew: String? = nil) {
        self.cookie = cookie
        self.renewResult = renewResult
        self.cookieAfterRenew = cookieAfterRenew
    }

    var renewCalls: Int { lock.sync { _renewCalls } }

    func authCookie() async -> String? { lock.sync { cookie } }

    func renew() async -> RenewResult {
        lock.sync {
            _renewCalls += 1
            if renewResult == .renewed { cookie = cookieAfterRenew }
            return renewResult
        }
    }
}
