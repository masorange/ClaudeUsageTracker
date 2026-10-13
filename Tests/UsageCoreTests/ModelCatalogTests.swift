import XCTest
@testable import UsageCore

final class ModelCatalogTests: XCTestCase {
    private func catalog() throws -> [CatalogEntry] {
        let models = try JSONDecoder.api.decode(ProxyModelListFixture.self, from: Fixture.data("litellm-models")).data
        let prices = try LiteLLMClient.decodeCostMap(Fixture.data("litellm-cost-map"))
        return ModelCatalog.build(models: models, prices: prices)
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

    func testCurrentPriceComesFromTheProxyDeployment() throws {
        let entries = try catalog()
        // Campaign route (no suffix → tier "free" deployment): Sonnet 5.5 at half price.
        let sonnet = try entry("claude-sonnet-5-5", in: entries)
        XCTAssertEqual(sonnet.inputPerMillion ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(sonnet.outputPerMillion ?? -1, 5, accuracy: 1e-9)
        XCTAssertEqual(sonnet.listInputPerMillion ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(sonnet.listOutputPerMillion ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(sonnet.discount ?? 0, 0.5, accuracy: 1e-9)
        // Vertex route → tier "paid" deployment at list price.
        let vertex = try entry("claude-sonnet-5-5-vertex", in: entries)
        XCTAssertEqual(vertex.inputPerMillion ?? -1, 2, accuracy: 1e-9)
        XCTAssertNil(vertex.discount)
        // Free campaign.
        let haiku = try entry("claude-haiku-5-5", in: entries)
        XCTAssertEqual(haiku.inputPerMillion, 0)
        XCTAssertEqual(haiku.discount ?? 0, 1, accuracy: 1e-9)
        // Opus 5.5's campaign ended: deployment back at list price.
        let opus = try entry("claude-opus-5-5", in: entries)
        XCTAssertEqual(opus.inputPerMillion ?? -1, 4, accuracy: 1e-9)
        XCTAssertNil(opus.discount)
    }

    func testModelsWithoutDeploymentEntryUseTheListPrice() throws {
        let gpt = try entry("gpt-5", in: try catalog())
        XCTAssertEqual(gpt.inputPerMillion ?? -1, 1.25, accuracy: 1e-9)
        XCTAssertEqual(gpt.listInputPerMillion ?? -1, 1.25, accuracy: 1e-9)
        XCTAssertNil(gpt.discount)
    }

    func testVersionParsing() {
        let cases: [(String, [Int])] = [
            ("claude-opus-5-5", [5, 5]), ("claude-haiku-4-5-20251001", [4, 5]), ("claude-opus-5-5-vertex", [5, 5]),
            ("gpt-5.4-mini", [5, 4]), ("gemini-2.5-flash-lite", [2, 5]), ("llama-3.3-70b", [3, 3]), ("o3-mini", [3]),
            ("gpt-4o", [4]), ("qwen3.6", [3, 6]), ("kimi-k2-thinking", [2]), ("deepseek-v3.2", [3, 2]),
            ("gemma-4-26b-a4b-it", [4]), ("claude-sonnet", []), ("gpt-oss-120b", []),
        ]
        for (id, expected) in cases {
            XCTAssertEqual(ModelCatalog.version(of: id), expected, id)
        }
    }

    func testSortsNewestFirstWithinProvider() throws {
        let entries = try catalog()
        XCTAssertEqual(entries.first?.provider, .anthropic)
        XCTAssertEqual(entries.last?.provider, .other)
        let anthropic = entries.filter { $0.provider == .anthropic }.map(\.id)
        XCTAssertEqual(Array(anthropic.prefix(7)), [
            "claude-opus-5-5", "claude-opus-5-5-vertex", "claude-sonnet-5-5", "claude-sonnet-5-5-vertex",
            "claude-haiku-5-5", "claude-haiku-5-5-vertex", "claude-fable-5-1",
        ])
        func index(_ id: String) -> Int { anthropic.firstIndex(of: id) ?? .max }
        XCTAssertLessThan(index("claude-opus-4-8"), index("claude-opus-4-7"))
        XCTAssertLessThan(index("claude-opus-4-7"), index("claude-opus-4-6"))
        XCTAssertLessThan(index("claude-opus-4-6"), index("claude-opus-4-5"))
        XCTAssertEqual(Set(anthropic.suffix(2)), ["claude-sonnet", "claude-opus"], "aliases last")
        let openai = entries.filter { $0.provider == .openai }.map(\.id)
        func oindex(_ id: String) -> Int { openai.firstIndex(of: id) ?? .max }
        XCTAssertLessThan(oindex("gpt-5.4"), oindex("gpt-5"))
        XCTAssertLessThan(oindex("gpt-5"), oindex("gpt-4.1"))
        XCTAssertLessThan(oindex("gpt-4.1"), oindex("gpt-3.5-turbo"))
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

    func testPruneKeepsListPriceAndDeploymentsOfListedModels() throws {
        let models = [ProxyModel(id: "claude-opus-5-5-vertex"), ProxyModel(id: "unknown-model")]
        let full = try LiteLLMClient.decodeCostMap(Fixture.data("litellm-cost-map"))
        let pruned = ModelCatalog.prune(full, for: models)
        XCTAssertEqual(Set(pruned.keys), ["claude-opus-5-5", "f8fb6248-f83e-423c-897e-c503736ae548", "b49a014d-3d9e-423a-b134-4631636b2406"])
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
