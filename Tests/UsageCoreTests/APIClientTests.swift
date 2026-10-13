import XCTest
@testable import UsageCore

final class APIClientTests: XCTestCase {
    private let googleRedirect = StubURLProtocol.Reply(status: 302, headers: ["Location": "https://accounts.google.com/o/oauth2/v2/auth?client_id=x"], body: Data())

    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private func client(_ store: SessionStore) -> APIClient {
        APIClient(store: store, configuration: StubURLProtocol.configuration)
    }

    private func meReply() throws -> StubURLProtocol.Reply {
        StubURLProtocol.Reply(body: try Fixture.data("me"))
    }

    func testSendsCookieAndBuildsURL() async throws {
        let reply = try meReply()
        StubURLProtocol.handler = { _ in reply }
        _ = try await client(FakeSessionStore(cookie: "abc")).me()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://ai-platform.cloud.masorange.es/api/v1/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Host-GCP_IAP_AUTH_TOKEN_=abc")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testDailyQueryUsesLiteLLMProvider() async throws {
        StubURLProtocol.handler = { _ in .init(body: Data("[]".utf8)) }
        _ = try await client(FakeSessionStore(cookie: "abc")).daily(start: "2026-10-01", end: "2026-10-13")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.absoluteString,
                       "https://ai-platform.cloud.masorange.es/api/v1/spend/daily?end=2026-10-13&provider=litellm&start=2026-10-01")
    }

    func testRenewsOnceOnRedirectToGoogle() async throws {
        let ok = try meReply()
        let redirect = googleRedirect
        StubURLProtocol.handler = { request in
            request.value(forHTTPHeaderField: "Cookie")?.hasSuffix("=new") == true ? ok : redirect
        }
        let store = FakeSessionStore(cookie: "old", renewResult: true, cookieAfterRenew: "new")
        let me = try await client(store).me()
        XCTAssertEqual(me.teams, ["Bronze"])
        XCTAssertEqual(store.renewCalls, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testNeedsLoginWhenRenewFails() async {
        let redirect = googleRedirect
        StubURLProtocol.handler = { _ in redirect }
        let store = FakeSessionStore(cookie: "old", renewResult: false)
        await assertThrows(.needsLogin) { _ = try await self.client(store).me() }
        XCTAssertEqual(store.renewCalls, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testNeedsLoginWhenStillUnauthorizedAfterRenew() async {
        StubURLProtocol.handler = { _ in .init(status: 401) }
        let store = FakeSessionStore(cookie: "old", renewResult: true, cookieAfterRenew: "new")
        await assertThrows(.needsLogin) { _ = try await self.client(store).me() }
        XCTAssertEqual(store.renewCalls, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testNoCookieTriesSilentRenewFirst() async throws {
        let ok = try meReply()
        StubURLProtocol.handler = { _ in ok }
        let store = FakeSessionStore(cookie: nil, renewResult: true, cookieAfterRenew: "new")
        _ = try await client(store).me()
        XCTAssertEqual(store.renewCalls, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testNoCookieAndNoSessionNeedsLogin() async {
        let store = FakeSessionStore(cookie: nil, renewResult: false)
        await assertThrows(.needsLogin) { _ = try await self.client(store).me() }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testServerErrorDoesNotRenew() async {
        StubURLProtocol.handler = { _ in .init(status: 500) }
        let store = FakeSessionStore(cookie: "abc")
        await assertThrows(.server(500)) { _ = try await self.client(store).me() }
        XCTAssertEqual(store.renewCalls, 0)
    }

    func testMalformedJSONIsDecodingError() async {
        StubURLProtocol.handler = { _ in .init(body: Data("<html>".utf8)) }
        do {
            _ = try await client(FakeSessionStore(cookie: "abc")).me()
            XCTFail("expected decoding error")
        } catch APIError.decoding {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testOfflineIsNetworkError() async {
        StubURLProtocol.error = URLError(.notConnectedToInternet)
        do {
            _ = try await client(FakeSessionStore(cookie: "abc")).me()
            XCTFail("expected network error")
        } catch APIError.network {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testLoadBuildsReportFromAllEndpoints() async throws {
        let bodies: [String: Data] = [
            "/api/v1/me": try Fixture.data("me"),
            "/api/v1/me/month-glance": try Fixture.data("month-glance"),
            "/api/v1/spend/daily": try Fixture.data("daily"),
            "/api/v1/spend/by-model": try Fixture.data("by-model"),
            "/api/v1/data-freshness": try Fixture.data("data-freshness"),
        ]
        StubURLProtocol.handler = { request in
            bodies[request.url!.path].map { .init(body: $0) } ?? .init(status: 404)
        }
        let report = try await MonthReport.load(client: client(FakeSessionStore(cookie: "abc")),
                                                today: TestCalendar.date(2026, 10, 13), calendar: TestCalendar.madrid)
        XCTAssertEqual(report.spend, 10.5261903, accuracy: 1e-9)
        XCTAssertEqual(report.days.count, 13)
        XCTAssertEqual(report.models.first?.displayName, "Opus 5.5")
        let daily = StubURLProtocol.requests.first { $0.url?.path == "/api/v1/spend/daily" }
        XCTAssertEqual(daily?.url?.query, "end=2026-10-13&provider=litellm&start=2026-10-01")
    }

    func testLoadSurvivesFreshnessFailure() async throws {
        let bodies: [String: Data] = [
            "/api/v1/me": try Fixture.data("me"),
            "/api/v1/me/month-glance": try Fixture.data("month-glance"),
            "/api/v1/spend/daily": try Fixture.data("daily"),
            "/api/v1/spend/by-model": try Fixture.data("by-model"),
        ]
        StubURLProtocol.handler = { request in
            bodies[request.url!.path].map { .init(body: $0) } ?? .init(status: 500)
        }
        let report = try await MonthReport.load(client: client(FakeSessionStore(cookie: "abc")),
                                                today: TestCalendar.date(2026, 10, 13), calendar: TestCalendar.madrid)
        XCTAssertNil(report.dataUpdatedAt)
    }

    private func assertThrows(_ expected: APIError, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as APIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
