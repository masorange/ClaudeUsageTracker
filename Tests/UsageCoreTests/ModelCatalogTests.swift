import XCTest
@testable import UsageCore

final class ModelCatalogTests: XCTestCase {
    private func catalog(discounts: [String: Double] = [:]) throws -> [CatalogEntry] {
        let models = try JSONDecoder.api.decode(ProxyModelListFixture.self, from: Fixture.data("litellm-models")).data
        let prices = try LiteLLMClient.decodeCostMap(Fixture.data("litellm-cost-map"))
        return ModelCatalog.build(models: models, prices: prices, discounts: discounts)
    }

    private func entry(_ id: String, in entries: [CatalogEntry]) throws -> CatalogEntry {
        try XCTUnwrap(entries.first { $0.id == id }, id)
    }

    func testBuildsOneEntryPerModelWithPerMillionPrices() throws {
        let entries = try catalog()
        XCTAssertEqual(entries.count, 111)
        let opus = try entry("claude-opus-5-5", in: entries)
        XCTAssertEqual(opus.displayName, "Opus 5.5")
        XCTAssertEqual(opus.provider, .anthropic)
        XCTAssertEqual(opus.kind, .chat)
        XCTAssertEqual(opus.maxInputTokens, 1_000_000)
        XCTAssertEqual(opus.inputPerMillion ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(opus.outputPerMillion ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(opus.cacheReadPerMillion ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertEqual(opus.cacheWritePerMillion ?? 0, 5, accuracy: 1e-9)
        XCTAssertFalse(opus.isAlias)
        XCTAssertFalse(opus.isTest)
    }

    func testReadableNamesForNonClaudeModels() {
        let cases: [(String, String)] = [
            ("gpt-5", "GPT-5"), ("gpt-5.4-mini", "GPT-5.4 Mini"), ("gpt-4o", "GPT-4o"), ("gpt-oss-120b", "GPT-OSS 120B"),
            ("gemini-2.5-pro", "Gemini 2.5 Pro"), ("gemini-3.1-flash-lite", "Gemini 3.1 Flash Lite"),
            ("o3-mini", "o3 Mini"), ("text-embedding-3-small", "Text Embedding 3 Small"),
            ("deepseek-r1", "DeepSeek R1"), ("glm-4.7", "GLM 4.7"), ("kimi-k2-thinking", "Kimi K2 Thinking"),
            ("llama-4-maverick", "Llama 4 Maverick"), ("qwen3-coder", "Qwen3 Coder"), ("minimax-m2", "MiniMax M2"),
            ("gemini-2.5-flash-tts", "Gemini 2.5 Flash TTS"), ("claude-opus-5-5", "Opus 5.5"),
        ]
        for (id, expected) in cases {
            XCTAssertEqual(ModelCatalog.displayName(for: id), expected, id)
        }
    }

    func testVertexVariantUsesBasePriceAndProxyLimits() throws {
        let vertex = try entry("claude-opus-5-5-vertex", in: try catalog())
        XCTAssertEqual(vertex.displayName, "Opus 5.5 (Vertex)")
        XCTAssertEqual(vertex.inputPerMillion ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(vertex.maxInputTokens, 200_000)
    }

    func testKindsAndProviders() throws {
        let entries = try catalog()
        XCTAssertEqual(try entry("text-embedding-3-small", in: entries).kind, .embedding)
        XCTAssertEqual(try entry("gpt-image-1.5", in: entries).kind, .image)
        XCTAssertEqual(try entry("gpt-5", in: entries).provider, .openai)
        XCTAssertEqual(try entry("gemini-2.5-pro", in: entries).provider, .google)
        XCTAssertEqual(try entry("llama-4-scout", in: entries).provider, .meta)
        XCTAssertEqual(try entry("codestral", in: entries).provider, .mistral)
        XCTAssertEqual(try entry("deepseek-r1", in: entries).provider, .deepseek)
        XCTAssertEqual(try entry("glm-5", in: entries).provider, .zhipu)
        XCTAssertEqual(try entry("kimi-k2-thinking", in: entries).provider, .moonshot)
        XCTAssertEqual(try entry("o3", in: entries).provider, .openai)
    }

    func testInfersKindForModelsWithoutMode() throws {
        let entries = try catalog()
        XCTAssertEqual(try entry("claude-sonnet", in: entries).kind, .chat)
        XCTAssertEqual(try entry("gemini-embedding", in: entries).kind, .embedding)
        XCTAssertEqual(try entry("gemini-2.5-flash-tts", in: entries).kind, .other)
        XCTAssertEqual(try entry("veo-3.1-generate-001", in: entries).kind, .other)
        XCTAssertLessThan(entries.filter { $0.kind == .other }.count, 12)
    }

    func testAliasesAndTestEntries() throws {
        let entries = try catalog()
        let alias = try entry("claude-sonnet", in: entries)
        XCTAssertTrue(alias.isAlias)
        XCTAssertFalse(alias.hasPrice)
        XCTAssertFalse(try entry("veo-3.1-generate-001", in: entries).isAlias)
        XCTAssertTrue(try entry("fake-openai-endpoint", in: entries).isTest)
        XCTAssertTrue(try entry("claude-opus-5-vertex-prueba", in: entries).isTest)
        XCTAssertTrue(try entry("all-proxy-models", in: entries).isTest)
    }

    func testCampaignDiscountAppliesToAllVariants() throws {
        let entries = try catalog(discounts: ["Opus 5.5": 1.0])
        XCTAssertEqual(try entry("claude-opus-5-5", in: entries).discount, 1.0)
        XCTAssertEqual(try entry("claude-opus-5-5-vertex", in: entries).discount, 1.0)
        XCTAssertNil(try entry("claude-sonnet-5-5", in: entries).discount)
    }

    func testDiscountsFromMonthReport() throws {
        let report = MonthReport.build(me: try Fixture.decode("me"), glance: try Fixture.decode("month-glance"),
                                       daily: try Fixture.decode("daily"), byModel: try Fixture.decode("by-model"),
                                       freshness: nil, today: TestCalendar.date(2026, 10, 13), calendar: TestCalendar.madrid)
        let discounts = ModelCatalog.discounts(from: report)
        XCTAssertEqual(discounts["Opus 5.5"] ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(discounts["Sonnet 5.5"] ?? 0, 0.785005147941914, accuracy: 1e-9)
        XCTAssertTrue(ModelCatalog.discounts(from: nil).isEmpty)
    }

    func testSortsByProviderThenPricedFirst() throws {
        let entries = try catalog()
        XCTAssertEqual(entries.first?.provider, .anthropic)
        XCTAssertEqual(entries.last?.provider, .other)
        let anthropic = entries.filter { $0.provider == .anthropic }
        let firstUnpriced = try XCTUnwrap(anthropic.firstIndex { !$0.hasPrice })
        XCTAssertTrue(anthropic[firstUnpriced...].allSatisfy { !$0.hasPrice })
    }

    func testFilterByKindAndQuery() throws {
        let entries = try catalog()
        let embeddings = ModelCatalog.filter(entries, kind: .embedding, query: "")
        XCTAssertFalse(embeddings.isEmpty)
        XCTAssertTrue(embeddings.allSatisfy { $0.kind == .embedding })
        let opus = ModelCatalog.filter(entries, kind: nil, query: "  OPUS 5.5 ")
        XCTAssertEqual(Set(opus.map(\.id)), ["claude-opus-5-5", "claude-opus-5-5-vertex"])
        XCTAssertEqual(ModelCatalog.filter(entries, kind: nil, query: "").count, 111)
    }

    func testGroupedKeepsProviderOrder() throws {
        let groups = ModelCatalog.grouped(try catalog())
        XCTAssertEqual(groups.first?.provider, .anthropic)
        XCTAssertEqual(groups.map(\.provider), groups.map(\.provider).sorted())
    }

    func testPruneKeepsOnlyReferencedPrices() throws {
        let models = [ProxyModel(id: "claude-opus-5-5-vertex"), ProxyModel(id: "unknown-model")]
        let full = try LiteLLMClient.decodeCostMap(Fixture.data("litellm-cost-map"))
        let pruned = ModelCatalog.prune(full, for: models)
        XCTAssertEqual(Array(pruned.keys), ["claude-opus-5-5"])
    }
}

final class ProviderIconTests: XCTestCase {
    func testEveryKnownProviderHasAnIcon() {
        for provider in ModelProvider.allCases where provider != .other {
            XCTAssertNotNil(provider.icon, provider.rawValue)
        }
        XCTAssertNil(ModelProvider.other.icon)
    }

    func testMonochromeLogosHaveLightAndDarkVariants() {
        XCTAssertEqual(ModelProvider.openai.icon, ProviderIcon(name: "openai", hasAppearanceVariants: true))
        XCTAssertEqual(ModelProvider.anthropic.icon, ProviderIcon(name: "anthropic", hasAppearanceVariants: false))
        XCTAssertEqual(ProviderIcon(name: "openai", hasAppearanceVariants: true).fileName(dark: true), "openai-dark")
        XCTAssertEqual(ProviderIcon(name: "anthropic", hasAppearanceVariants: false).fileName(dark: true), "anthropic")
    }
}

/// Mirrors the private wrapper used by `LiteLLMClient` so tests can decode the fixture directly.
struct ProxyModelListFixture: Decodable {
    let data: [ProxyModel]
}
