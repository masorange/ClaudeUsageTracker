import Foundation
import os
import UsageCore

enum KeySource: Equatable {
    case stored, detected, none
}

enum CatalogState: Equatable {
    case idle, ok, noKey, invalidKey, offline, apiChanged
    case failed(String)
}

/// Loads the models available through LiteLLM and their list prices.
@MainActor
final class CatalogModel: ObservableObject {
    @Published private(set) var entries: [CatalogEntry] = []
    @Published private(set) var state: CatalogState = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var keySource: KeySource = .none

    private let client = LiteLLMClient()
    private let cache = CatalogCache.standard
    private let logger = Logger(subsystem: "com.claudeusage.tracker", category: "catalog")
    private var snapshot: CatalogSnapshot?
    private var discounts: [String: Double] = [:]

    init() {
        snapshot = cache.load()
        lastSuccess = snapshot?.modelsFetchedAt
        resolveKeySource()
        rebuild()
    }

    func updateDiscounts(from report: MonthReport?) {
        discounts = ModelCatalog.discounts(from: report)
        rebuild()
    }

    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < maxAge, state == .ok { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        resolveKeySource()
        guard let key = effectiveKey else {
            state = .noKey
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let models = try await client.models(key: key)
            var prices = snapshot?.prices ?? [:]
            var pricesFetchedAt = snapshot?.pricesFetchedAt
            if prices.isEmpty || !(snapshot?.pricesAreFresh() ?? false) {
                // Prices are optional: without them the list is still useful.
                if let full = try? await client.costMap() {
                    prices = ModelCatalog.prune(full, for: models)
                    pricesFetchedAt = Date()
                }
            }
            let fresh = CatalogSnapshot(models: models, prices: prices, modelsFetchedAt: Date(), pricesFetchedAt: pricesFetchedAt)
            snapshot = fresh
            cache.save(fresh)
            lastSuccess = fresh.modelsFetchedAt
            state = .ok
            rebuild()
        } catch LiteLLMError.invalidKey {
            state = .invalidKey
        } catch LiteLLMError.network {
            state = .offline
        } catch LiteLLMError.decoding(let detail) {
            logger.error("Catalog decoding failed: \(detail, privacy: .public)")
            state = .apiChanged
        } catch LiteLLMError.server(let status) {
            state = .failed("HTTP \(status)")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func saveKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        APIKeyStore.save(trimmed)
        await refresh()
    }

    func forgetKey() {
        APIKeyStore.delete()
        resolveKeySource()
        if keySource == .none {
            entries = []
            snapshot = nil
            cache.clear()
            state = .noKey
        }
    }

    private var detectedKey: String? {
        APIKeyLocator.detect(home: FileManager.default.homeDirectoryForCurrentUser,
                             environment: ProcessInfo.processInfo.environment)
    }

    private var effectiveKey: String? {
        APIKeyStore.load() ?? detectedKey
    }

    private func resolveKeySource() {
        if APIKeyStore.load() != nil {
            keySource = .stored
        } else if detectedKey != nil {
            keySource = .detected
        } else {
            keySource = .none
        }
    }

    private func rebuild() {
        guard let snapshot else { return }
        entries = ModelCatalog.build(models: snapshot.models, prices: snapshot.prices, discounts: discounts)
    }
}
