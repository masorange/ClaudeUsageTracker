import Foundation

public enum APIError: Error, Equatable {
    case needsLogin
    case network(String)
    case server(Int)
    case decoding(String)
}

/// Read-only client for the AI Platform API, authenticated with the IAP session cookie.
public final class APIClient: @unchecked Sendable {
    public static let baseURL = URL(string: "https://ai-platform.cloud.masorange.es/api/v1/")!
    public static let cookieName = "__Host-GCP_IAP_AUTH_TOKEN_"

    private let store: SessionStore
    private let session: URLSession

    public init(store: SessionStore, configuration: URLSessionConfiguration = .ephemeral) {
        self.store = store
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    public func me() async throws -> Me {
        try await get("me")
    }

    public func monthGlance() async throws -> MonthGlance {
        try await get("me/month-glance")
    }

    public func daily(start: String, end: String) async throws -> [DailySpend] {
        try await get("spend/daily", query: ["start": start, "end": end, "provider": MonthReport.provider])
    }

    public func byModel(start: String, end: String) async throws -> [ModelSpend] {
        try await get("spend/by-model", query: ["start": start, "end": end, "provider": MonthReport.provider])
    }

    public func dataFreshness() async throws -> DataFreshness {
        try await get("data-freshness", query: ["provider": MonthReport.provider])
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await fetch(path, query: query, mayRenew: true)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Performs the request. An expired session (IAP redirect to Google or 401) triggers one silent renewal + retry.
    private func fetch(_ path: String, query: [String: String], mayRenew: Bool) async throws -> Data {
        guard let cookie = await store.authCookie() else {
            guard mayRenew else { throw APIError.needsLogin }
            try await renewSession()
            return try await fetch(path, query: query, mayRenew: false)
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: Self.request(path: path, query: query, cookie: cookie))
        } catch let error as URLError {
            throw APIError.network(error.localizedDescription)
        } catch {
            throw APIError.network(String(describing: error))
        }
        guard let http = result.1 as? HTTPURLResponse else { throw APIError.network("Invalid response") }

        switch http.statusCode {
        case 200..<300:
            return result.0
        case 300..<400, 401:
            guard mayRenew else { throw APIError.needsLogin }
            try await renewSession()
            return try await fetch(path, query: query, mayRenew: false)
        default:
            throw APIError.server(http.statusCode)
        }
    }

    private func renewSession() async throws {
        switch await store.renew() {
        case .renewed: return
        case .needsLogin: throw APIError.needsLogin
        case .offline: throw APIError.network("offline")
        }
    }

    static func request(path: String, query: [String: String], cookie: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
        return request
    }
}

/// IAP answers expired sessions with a redirect to Google sign-in; we want to see that response, not follow it.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
