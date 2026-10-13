import Foundation

/// One entry of the proxy's `GET /v1/models`.
public struct ProxyModel: Codable, Equatable, Sendable {
    public let id: String
    public let mode: String?
    public let maxInputTokens: Int?
    public let maxOutputTokens: Int?

    public init(id: String, mode: String? = nil, maxInputTokens: Int? = nil, maxOutputTokens: Int? = nil) {
        self.id = id
        self.mode = mode
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
    }
}

private struct ProxyModelList: Decodable {
    let data: [ProxyModel]
}

/// List price of a model in LiteLLM's public cost map (USD per token). Fields that don't parse become nil.
public struct ModelPrice: Codable, Equatable, Sendable {
    public var inputCostPerToken: Double?
    public var outputCostPerToken: Double?
    public var cacheReadInputTokenCost: Double?
    public var cacheCreationInputTokenCost: Double?
    public var maxInputTokens: Int?
    public var maxOutputTokens: Int?
    public var mode: String?

    enum CodingKeys: String, CodingKey {
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case cacheReadInputTokenCost = "cache_read_input_token_cost"
        case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
        case maxInputTokens = "max_input_tokens"
        case maxOutputTokens = "max_output_tokens"
        case mode
    }

    public init(inputCostPerToken: Double? = nil, outputCostPerToken: Double? = nil,
                cacheReadInputTokenCost: Double? = nil, cacheCreationInputTokenCost: Double? = nil,
                maxInputTokens: Int? = nil, maxOutputTokens: Int? = nil, mode: String? = nil) {
        self.inputCostPerToken = inputCostPerToken
        self.outputCostPerToken = outputCostPerToken
        self.cacheReadInputTokenCost = cacheReadInputTokenCost
        self.cacheCreationInputTokenCost = cacheCreationInputTokenCost
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.mode = mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputCostPerToken = try? container.decodeIfPresent(Double.self, forKey: .inputCostPerToken)
        outputCostPerToken = try? container.decodeIfPresent(Double.self, forKey: .outputCostPerToken)
        cacheReadInputTokenCost = try? container.decodeIfPresent(Double.self, forKey: .cacheReadInputTokenCost)
        cacheCreationInputTokenCost = try? container.decodeIfPresent(Double.self, forKey: .cacheCreationInputTokenCost)
        maxInputTokens = try? container.decodeIfPresent(Int.self, forKey: .maxInputTokens)
        maxOutputTokens = try? container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        mode = try? container.decodeIfPresent(String.self, forKey: .mode)
    }
}

/// Skips cost-map entries that are not objects instead of failing the whole map.
private struct LossyPrice: Decodable {
    let value: ModelPrice?

    init(from decoder: Decoder) throws {
        value = try? ModelPrice(from: decoder)
    }
}

public enum LiteLLMError: Error, Equatable {
    case invalidKey
    case network(String)
    case server(Int)
    case decoding(String)
}

/// Client for the company LiteLLM proxy: the user's available models (needs their key) and public list prices.
public final class LiteLLMClient: @unchecked Sendable {
    public static let baseURL = URL(string: "https://llm.tools.cloud.masorange.es/")!

    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    public func models(key: String) async throws -> [ProxyModel] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/models"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        do {
            return try JSONDecoder.api.decode(ProxyModelList.self, from: data).data
        } catch {
            throw LiteLLMError.decoding(String(describing: error))
        }
    }

    public func costMap() async throws -> [String: ModelPrice] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("public/litellm_model_cost_map"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        do {
            return try Self.decodeCostMap(data)
        } catch {
            throw LiteLLMError.decoding(String(describing: error))
        }
    }

    /// Plain decoder on purpose: `convertFromSnakeCase` would rewrite dictionary keys like `vertex_ai/...`.
    public static func decodeCostMap(_ data: Data) throws -> [String: ModelPrice] {
        let raw = try JSONDecoder().decode([String: LossyPrice].self, from: data)
        return raw.compactMapValues(\.value).filter { $0.key != "sample_spec" }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            throw LiteLLMError.network(error.localizedDescription)
        } catch {
            throw LiteLLMError.network(String(describing: error))
        }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return result.0
        case 401, 403: throw LiteLLMError.invalidKey
        default: throw LiteLLMError.server(status)
        }
    }
}
