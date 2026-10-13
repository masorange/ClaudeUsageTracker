import XCTest
@testable import UsageCore

final class LiteLLMClientTests: XCTestCase {
    override func setUp() { StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset() }

    private var client: LiteLLMClient { LiteLLMClient(configuration: StubURLProtocol.configuration) }

    func testModelsSendsBearerKeyAndDecodes() async throws {
        let body = try Fixture.data("litellm-models")
        StubURLProtocol.handler = { _ in .init(body: body) }
        let models = try await client.models(key: "sk-test")
        XCTAssertEqual(models.count, 111)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://llm.tools.cloud.masorange.es/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let opus = try XCTUnwrap(models.first { $0.id == "claude-opus-5-5" })
        XCTAssertEqual(opus.mode, "chat")
        XCTAssertEqual(opus.maxInputTokens, 1_000_000)
        XCTAssertEqual(opus.maxOutputTokens, 128_000)
    }

    func testInvalidKeyOn401And403() async {
        for status in [401, 403] {
            StubURLProtocol.handler = { _ in .init(status: status) }
            do {
                _ = try await client.models(key: "sk-bad")
                XCTFail("expected invalidKey for \(status)")
            } catch let error as LiteLLMError {
                XCTAssertEqual(error, .invalidKey)
            } catch {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testCostMapHasNoAuthHeaderAndSkipsSampleSpec() async throws {
        let body = try Fixture.data("litellm-cost-map")
        StubURLProtocol.handler = { _ in .init(body: body) }
        let prices = try await client.costMap()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://llm.tools.cloud.masorange.es/public/litellm_model_cost_map")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(prices["sample_spec"])
        let opus = try XCTUnwrap(prices["claude-opus-5-5"])
        XCTAssertEqual(opus.inputCostPerToken, 4e-06)
        XCTAssertEqual(opus.outputCostPerToken, 2e-05)
        XCTAssertEqual(opus.cacheReadInputTokenCost, 2e-07)
        XCTAssertEqual(opus.cacheCreationInputTokenCost, 5e-06)
    }

    func testCostMapKeepsRawKeys() throws {
        let json = Data(#"{"vertex_ai/claude-x_y":{"input_cost_per_token":1e-6,"mode":"chat"},"broken":"not an object","odd":{"input_cost_per_token":"free","max_input_tokens":8191.0}}"#.utf8)
        let prices = try LiteLLMClient.decodeCostMap(json)
        XCTAssertEqual(prices["vertex_ai/claude-x_y"]?.inputCostPerToken, 1e-6)
        XCTAssertNil(prices["broken"])
        XCTAssertNotNil(prices["odd"])
        XCTAssertNil(prices["odd"]?.inputCostPerToken)
    }

    func testServerAndNetworkErrors() async {
        StubURLProtocol.handler = { _ in .init(status: 502) }
        await assertThrows(.server(502)) { _ = try await self.client.models(key: "k") }
        StubURLProtocol.error = URLError(.notConnectedToInternet)
        do {
            _ = try await client.costMap()
            XCTFail("expected network error")
        } catch LiteLLMError.network {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func assertThrows(_ expected: LiteLLMError, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)")
        } catch let error as LiteLLMError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
