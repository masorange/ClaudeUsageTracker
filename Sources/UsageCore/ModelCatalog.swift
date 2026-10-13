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
    /// Price charged today by the proxy (its deployment price), falling back to the public list price.
    public let inputPerMillion: Double?
    public let outputPerMillion: Double?
    public let cacheReadPerMillion: Double?
    public let cacheWritePerMillion: Double?
    /// Public list price, shown struck through when a campaign makes the current price lower.
    public let listInputPerMillion: Double?
    public let listOutputPerMillion: Double?
    /// Current campaign discount (0…1) = 1 − current price / list price; nil when there is none.
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

    /// The proxy's own deployments appear in the cost map keyed by deployment id, with `base_model` and a routing
    /// `tier`. Verified 2026-10-13 with `x-litellm-model-id`: `claude-X` routes to the `free` deployment (where
    /// campaigns are priced) and `claude-X-vertex` to the `paid` one.
    static func deploymentPrice(for id: String, in prices: [String: ModelPrice]) -> ModelPrice? {
        let base = baseID(id)
        let wantedTier = id.hasSuffix(vertexSuffix) ? "paid" : "free"
        let candidates = prices.values.filter { price in
            guard let model = price.baseModel else { return false }
            return normalizedBase(model) == base
        }
        return candidates.first { $0.tier == wantedTier } ?? (candidates.count == 1 ? candidates.first : nil)
    }

    /// `claude-haiku-4-5@20251001` (Vertex naming) → `claude-haiku-4-5-20251001`.
    private static func normalizedBase(_ model: String) -> String {
        model.replacingOccurrences(of: "@", with: "-")
    }

    /// Keeps only the cost-map entries used by `models` (what we persist on disk): list prices and deployments.
    public static func prune(_ prices: [String: ModelPrice], for models: [ProxyModel]) -> [String: ModelPrice] {
        var pruned: [String: ModelPrice] = [:]
        let bases = Set(models.map { baseID($0.id) })
        for model in models {
            if let key = priceKeys(for: model.id).first(where: { prices[$0] != nil }) {
                pruned[key] = prices[key]
            }
        }
        for (key, price) in prices {
            if let model = price.baseModel, bases.contains(normalizedBase(model)) { pruned[key] = price }
        }
        return pruned
    }

    /// Version numbers in a model id, used to sort newest first: `claude-opus-4-8` → [4, 8], `gpt-5.4-mini` → [5, 4].
    /// Dates (`20251001`) and parameter counts (`70b`) are ignored.
    public static func version(of id: String) -> [Int] {
        let tokens = baseID(id.split(separator: "/").last.map(String.init) ?? id).lowercased().split(separator: "-").map(String.init)
        var numbers: [Int] = []
        for token in tokens {
            let isDate = token.count == 8 && token.allSatisfy(\.isNumber)
            let isSize = token.hasSuffix("b") && token.dropLast().allSatisfy { $0.isNumber || $0 == "." } && token.count > 1
            if isDate || isSize { continue }
            let isPlainNumber = token.allSatisfy(\.isNumber)
            if !numbers.isEmpty {
                // Claude ids spell versions as separate tokens (opus-4-8); anything else ends the version.
                guard isPlainNumber else { break }
                numbers.append(Int(token) ?? 0)
                continue
            }
            guard let range = token.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { continue }
            numbers = token[range].split(separator: ".").compactMap { Int($0) }
        }
        return numbers
    }

    /// Bigger Claude tiers first among models of the same version.
    private static func familyRank(_ id: String) -> Int {
        let lower = id.lowercased()
        for (index, family) in ["fable", "opus", "sonnet", "haiku"].enumerated() where lower.contains(family) {
            return index
        }
        return 4
    }

    private static func perMillion(_ value: Double?) -> Double? {
        value.map { $0 * 1_000_000 }
    }

    /// 1 − current / list on the input price (output when input is not priced); nil below 0.5 %.
    static func campaignDiscount(current: ModelPrice?, list: ModelPrice?) -> Double? {
        guard let current, let list else { return nil }
        let pairs = [(current.inputCostPerToken, list.inputCostPerToken), (current.outputCostPerToken, list.outputCostPerToken)]
        guard let (now, base) = pairs.first(where: { ($0.1 ?? 0) > 0 && $0.0 != nil }).map({ ($0.0!, $0.1!) }) else { return nil }
        let discount = 1 - now / base
        return discount > 0.005 ? discount : nil
    }

    public static func build(models: [ProxyModel], prices: [String: ModelPrice]) -> [CatalogEntry] {
        models.map { model in
            let list = price(for: model.id, in: prices)
            let current = deploymentPrice(for: model.id, in: prices) ?? list
            let lower = model.id.lowercased()
            let hasPrice = current?.inputCostPerToken != nil || current?.outputCostPerToken != nil
            return CatalogEntry(
                id: model.id,
                displayName: displayName(for: model.id),
                provider: ModelProvider(modelID: model.id),
                kind: ModelKind(mode: model.mode ?? list?.mode ?? current?.mode, id: model.id),
                maxInputTokens: model.maxInputTokens ?? list?.maxInputTokens,
                maxOutputTokens: model.maxOutputTokens ?? list?.maxOutputTokens,
                inputPerMillion: perMillion(current?.inputCostPerToken),
                outputPerMillion: perMillion(current?.outputCostPerToken),
                cacheReadPerMillion: perMillion(current?.cacheReadInputTokenCost ?? list?.cacheReadInputTokenCost),
                cacheWritePerMillion: perMillion(current?.cacheCreationInputTokenCost ?? list?.cacheCreationInputTokenCost),
                listInputPerMillion: perMillion(list?.inputCostPerToken),
                listOutputPerMillion: perMillion(list?.outputCostPerToken),
                discount: campaignDiscount(current: current, list: list),
                isTest: lower.contains("fake-") || lower.contains("-prueba") || lower == "all-proxy-models",
                isAlias: !hasPrice && !model.id.contains(where: \.isNumber)
            )
        }
        .sorted(by: newestFirst)
    }

    /// Provider order, then newest version first; same version: bigger family first, Vertex right after its base;
    /// models without a version (aliases) last.
    static func newestFirst(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
        if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
        let (lv, rv) = (version(of: lhs.id), version(of: rhs.id))
        if lv.isEmpty != rv.isEmpty { return !lv.isEmpty }
        if lv != rv { return rv.lexicographicallyPrecedes(lv) }
        let (lf, rf) = (familyRank(lhs.id), familyRank(rhs.id))
        if lf != rf { return lf < rf }
        let (lb, rb) = (baseID(lhs.id), baseID(rhs.id))
        if lb != rb { return lb.localizedStandardCompare(rb) == .orderedAscending }
        return !lhs.id.hasSuffix(vertexSuffix) && rhs.id.hasSuffix(vertexSuffix)
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
