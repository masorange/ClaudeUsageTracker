import XCTest
@testable import UsageCore

final class CatalogCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: CatalogCache!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cache = CatalogCache(fileURL: directory.appendingPathComponent("catalog.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private let snapshot = CatalogSnapshot(
        models: [ProxyModel(id: "claude-opus-5-5", mode: "chat", maxInputTokens: 1_000_000, maxOutputTokens: 128_000)],
        prices: ["vertex_ai/claude-opus-5-5": ModelPrice(inputCostPerToken: 4e-06, outputCostPerToken: 2e-05)],
        modelsFetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
        pricesFetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    func testRoundTripKeepsRawPriceKeys() {
        cache.save(snapshot)
        XCTAssertEqual(cache.load(), snapshot)
    }

    func testPricesFreshForOneDay() {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(snapshot.pricesAreFresh(now: fetched.addingTimeInterval(86_000)))
        XCTAssertFalse(snapshot.pricesAreFresh(now: fetched.addingTimeInterval(86_500)))
        var noPrices = snapshot
        noPrices.pricesFetchedAt = nil
        XCTAssertFalse(noPrices.pricesAreFresh(now: fetched))
    }

    func testClearAndMissingFile() {
        XCTAssertNil(cache.load())
        cache.save(snapshot)
        cache.clear()
        XCTAssertNil(cache.load())
    }
}
