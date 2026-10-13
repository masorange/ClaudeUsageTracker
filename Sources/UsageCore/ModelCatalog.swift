import Foundation

public enum ModelKind: String, Codable, CaseIterable, Sendable {
    case chat, embedding, image, other

    /// Kind from an explicit LiteLLM mode, or inferred from the id when no source provides one.
    init(mode: String?, id: String) {
        switch mode {
        case "chat", "responses", "completion": self = .chat
        case "embedding": self = .embedding
        case "image_generation", "image_edit": self = .image
        case .some: self = .other
        case .none:
            let lower = id.lowercased()
            if lower.contains("embedding") { self = .embedding }
            else if lower.contains("image") { self = .image }
            else if ["tts", "veo", "audio"].contains(where: lower.contains) { self = .other }
            else { self = .chat }
        }
    }
}

public enum ModelProvider: String, Codable, CaseIterable, Comparable, Sendable {
    // Declaration order is the display order.
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Google"
    case meta = "Meta"
    case mistral = "Mistral"
    case deepseek = "DeepSeek"
    case minimax = "MiniMax"
    case moonshot = "Moonshot"
    case qwen = "Qwen"
    case zhipu = "Zhipu"
    case other = "Other"

    public static func < (lhs: ModelProvider, rhs: ModelProvider) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// Brand icon bundled with the app (nil for `.other`).
    public var icon: ProviderIcon? {
        switch self {
        case .openai, .moonshot: return ProviderIcon(name: rawValue.lowercased(), hasAppearanceVariants: true)
        case .other: return nil
        default: return ProviderIcon(name: rawValue.lowercased(), hasAppearanceVariants: false)
        }
    }

    public init(modelID: String) {
        // Accept both proxy ids (`claude-opus-5-5`) and spend ids with a provider prefix (`anthropic/claude-…`).
        let id = (modelID.split(separator: "/").last.map(String.init) ?? modelID).lowercased()
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { id.hasPrefix($0) } }
        if starts("claude") { self = .anthropic }
        else if starts("gpt", "o1", "o3", "o4", "text-embedding", "codex") { self = .openai }
        else if starts("gemini", "gemma", "veo") { self = .google }
        else if starts("llama") { self = .meta }
        else if starts("mistral", "codestral") { self = .mistral }
        else if starts("deepseek") { self = .deepseek }
        else if starts("minimax") { self = .minimax }
        else if starts("kimi") { self = .moonshot }
        else if starts("qwen") { self = .qwen }
        else if starts("glm") { self = .zhipu }
        else { self = .other }
    }
}

/// File name of a bundled provider logo; monochrome logos ship a `-light` and a `-dark` variant.
public struct ProviderIcon: Equatable, Sendable {
    public let name: String
    public let hasAppearanceVariants: Bool

    public init(name: String, hasAppearanceVariants: Bool) {
        self.name = name
        self.hasAppearanceVariants = hasAppearanceVariants
    }

    public func fileName(dark: Bool) -> String {
        hasAppearanceVariants ? "\(name)-\(dark ? "dark" : "light")" : name
    }
}

/// One available model with its list price per 1M tokens (USD).
public struct CatalogEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let provider: ModelProvider
    public let kind: ModelKind
    public let maxInputTokens: Int?
    public let maxOutputTokens: Int?
    public let inputPerMillion: Double?
    public let outputPerMillion: Double?
    public let cacheReadPerMillion: Double?
    public let cacheWritePerMillion: Double?
    /// Campaign discount observed in this month's spend (0…1).
    public let discount: Double?
    public let isTest: Bool
    public let isAlias: Bool

    public var hasPrice: Bool { inputPerMillion != nil || outputPerMillion != nil }
}

public enum ModelCatalog {
    private static let vertexSuffix = "-vertex"

    /// Cost-map keys tried for a proxy model id, first hit wins.
    static func priceKeys(for id: String) -> [String] {
        let base = baseID(id)
        return [id, base, "anthropic/\(id)", "vertex_ai/\(base)", "gemini/\(id)", "openai/\(id)"]
    }

    static func price(for id: String, in prices: [String: ModelPrice]) -> ModelPrice? {
        priceKeys(for: id).lazy.compactMap { prices[$0] }.first
    }

    private static func baseID(_ id: String) -> String {
        id.hasSuffix(vertexSuffix) ? String(id.dropLast(vertexSuffix.count)) : id
    }

    public static func displayName(for id: String) -> String {
        let base = baseID(id)
        let claudeName = ModelNames.displayName(for: base)
        guard claudeName != base else { return readableName(for: id) }
        return id.hasSuffix(vertexSuffix) ? "\(claudeName) (Vertex)" : claudeName
    }

    private static let wordOverrides = ["gpt": "GPT", "oss": "OSS", "glm": "GLM", "tts": "TTS",
                                        "deepseek": "DeepSeek", "minimax": "MiniMax", "openai": "OpenAI"]

    /// `gpt-5.4-mini` → `GPT-5.4 Mini`, `gemini-2.5-pro` → `Gemini 2.5 Pro`, `deepseek-r1` → `DeepSeek R1`.
    static func readableName(for id: String) -> String {
        let tokens = id.split(separator: "-").map { word(String($0)) }
        guard let first = tokens.first else { return id }
        // OpenAI writes its family with a hyphen: GPT-5, GPT-4o, GPT-OSS.
        if first == "GPT", tokens.count > 1 {
            return (["GPT-\(tokens[1])"] + tokens.dropFirst(2)).joined(separator: " ")
        }
        return tokens.joined(separator: " ")
    }

    private static func word(_ token: String) -> String {
        let lower = token.lowercased()
        if let override = wordOverrides[lower] { return override }
        guard let firstChar = lower.first else { return token }
        let hasDigit = lower.contains(where: \.isNumber)
        if firstChar == "o", hasDigit, lower.dropFirst().allSatisfy({ $0.isNumber }) { return lower }   // o1, o3, o4
        if firstChar.isNumber {
            // Parameter counts are upper-cased (120B); version suffixes like 4o stay as written.
            return lower.hasSuffix("b") && lower.dropLast().allSatisfy({ $0.isNumber || $0 == "." }) ? lower.uppercased() : lower
        }
        if hasDigit { return lower.count <= 4 ? lower.uppercased() : lower.prefix(1).uppercased() + lower.dropFirst() }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// Keeps only the cost-map entries used by `models` (what we persist on disk).
    public static func prune(_ prices: [String: ModelPrice], for models: [ProxyModel]) -> [String: ModelPrice] {
        var pruned: [String: ModelPrice] = [:]
        for model in models {
            if let key = priceKeys(for: model.id).first(where: { prices[$0] != nil }) {
                pruned[key] = prices[key]
            }
        }
        return pruned
    }

    /// Campaign discounts by display name, from the models used this month.
    public static func discounts(from report: MonthReport?) -> [String: Double] {
        let pairs = report?.models.compactMap { model in model.discount.map { (model.displayName, $0) } } ?? []
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    public static func build(models: [ProxyModel], prices: [String: ModelPrice], discounts: [String: Double]) -> [CatalogEntry] {
        models.map { model in
            let price = price(for: model.id, in: prices)
            let lower = model.id.lowercased()
            let entry = CatalogEntry(
                id: model.id,
                displayName: displayName(for: model.id),
                provider: ModelProvider(modelID: model.id),
                kind: ModelKind(mode: model.mode ?? price?.mode, id: model.id),
                maxInputTokens: model.maxInputTokens ?? price?.maxInputTokens,
                maxOutputTokens: model.maxOutputTokens ?? price?.maxOutputTokens,
                inputPerMillion: price?.inputCostPerToken.map { $0 * 1_000_000 },
                outputPerMillion: price?.outputCostPerToken.map { $0 * 1_000_000 },
                cacheReadPerMillion: price?.cacheReadInputTokenCost.map { $0 * 1_000_000 },
                cacheWritePerMillion: price?.cacheCreationInputTokenCost.map { $0 * 1_000_000 },
                discount: discounts[ModelNames.displayName(for: baseID(model.id))],
                isTest: lower.contains("fake-") || lower.contains("-prueba") || lower == "all-proxy-models",
                isAlias: false
            )
            let isAlias = !entry.hasPrice && !model.id.contains(where: \.isNumber)
            return CatalogEntry(id: entry.id, displayName: entry.displayName, provider: entry.provider, kind: entry.kind,
                                maxInputTokens: entry.maxInputTokens, maxOutputTokens: entry.maxOutputTokens,
                                inputPerMillion: entry.inputPerMillion, outputPerMillion: entry.outputPerMillion,
                                cacheReadPerMillion: entry.cacheReadPerMillion, cacheWritePerMillion: entry.cacheWritePerMillion,
                                discount: entry.discount, isTest: entry.isTest, isAlias: isAlias)
        }
        .sorted { lhs, rhs in
            if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
            if lhs.hasPrice != rhs.hasPrice { return lhs.hasPrice }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    public static func filter(_ entries: [CatalogEntry], kind: ModelKind?, query: String) -> [CatalogEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            (kind == nil || entry.kind == kind)
                && (needle.isEmpty || entry.displayName.lowercased().contains(needle) || entry.id.lowercased().contains(needle))
        }
    }

    public static func grouped(_ entries: [CatalogEntry]) -> [(provider: ModelProvider, entries: [CatalogEntry])] {
        let byProvider = Dictionary(grouping: entries, by: \.provider)
        return byProvider.keys.sorted().map { ($0, byProvider[$0]!) }
    }
}
