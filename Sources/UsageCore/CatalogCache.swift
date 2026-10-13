import Foundation

/// Last fetched catalog: available models plus the pruned list prices.
public struct CatalogSnapshot: Codable, Equatable, Sendable {
    public var models: [ProxyModel]
    public var prices: [String: ModelPrice]
    public var modelsFetchedAt: Date
    public var pricesFetchedAt: Date?
    /// Model ids the prices were pruned for; nil in caches written before this field existed.
    public var pricedModelIDs: [String]?

    public init(models: [ProxyModel], prices: [String: ModelPrice], modelsFetchedAt: Date, pricesFetchedAt: Date?,
                pricedModelIDs: [String]? = nil) {
        self.models = models
        self.prices = prices
        self.modelsFetchedAt = modelsFetchedAt
        self.pricesFetchedAt = pricesFetchedAt
        self.pricedModelIDs = pricedModelIDs
    }

    /// The 2 MB cost map is downloaded at most once a day.
    public func pricesAreFresh(now: Date = Date(), maxAge: TimeInterval = 86_400) -> Bool {
        guard let pricesFetchedAt else { return false }
        return now.timeIntervalSince(pricesFetchedAt) < maxAge
    }

    /// Prices must be re-downloaded when they are old or were pruned for a different model list
    /// (otherwise a model added to the proxy would stay unpriced until the next day).
    public func needsPriceRefresh(for models: [ProxyModel], now: Date = Date()) -> Bool {
        guard pricesAreFresh(now: now), let pricedModelIDs else { return true }
        return Set(pricedModelIDs) != Set(models.map(\.id))
    }
}

public struct CatalogCache: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/ClaudeUsageTracker/catalog.json`
    public static var standard: CatalogCache {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CatalogCache(fileURL: support.appendingPathComponent("ClaudeUsageTracker/catalog.json"))
    }

    public func load() -> CatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CatalogSnapshot.self, from: data)
    }

    public func save(_ snapshot: CatalogSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
