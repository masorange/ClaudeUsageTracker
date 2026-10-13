import Foundation
import os
import UsageCore

enum KeySource: Equatable {
    case stored, detected, none
}

enum CatalogState: Equatable {
    case idle, ok, noKey, invalidKey, offline, apiChanged, keychainDenied
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
    /// False until the key source has been resolved (avoids flashing the key prompt).
    @Published private(set) var isPrepared = false

    private let client = LiteLLMClient()
    private let cache = CatalogCache.standard
    private let logger = Logger(subsystem: "com.claudeusage.tracker", category: "catalog")
    private var snapshot: CatalogSnapshot?
    private var discounts: [String: Double] = [:]
    /// Keychain result cached for the whole run: ad-hoc signed builds trigger a macOS prompt on each read
    /// after an upgrade, so we read at most once (lazily, never at launch).
    private var storedKey: APIKeyStore.LoadResult?
    private var loadTask: Task<Void, Never>?
    private var refreshQueued = false

    init() {
        snapshot = cache.load()
        lastSuccess = snapshot?.modelsFetchedAt
        rebuild()
    }

    func updateDiscounts(from report: MonthReport?) {
        discounts = ModelCatalog.discounts(from: report)
        rebuild()
    }

    /// Resolves where the key comes from (reads the Keychain the first time only).
    func prepare() {
        if storedKey == nil { storedKey = APIKeyStore.load() }
        switch storedKey {
        case .found: keySource = .stored
        default: keySource = detectedKey != nil ? .detected : .none
        }
        isPrepared = true
    }

    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < maxAge, state == .ok { return }
        await refresh()
    }

    func refresh() async {
        if let loadTask {
            refreshQueued = true
            await loadTask.value
            return
        }
        // Unstructured on purpose: a view disappearing must not cancel a half-done download.
        let task = Task { await self.load() }
        loadTask = task
        await task.value
        loadTask = nil
        if refreshQueued {
            refreshQueued = false
            await refresh()
        }
    }

    func saveKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if APIKeyStore.save(trimmed) {
            storedKey = .found(trimmed)
        } else {
            logger.error("Could not save the LiteLLM key in the Keychain")
            state = .failed("Keychain")
        }
        await refresh()
    }

    func forgetKey() {
        APIKeyStore.delete()
        storedKey = .notFound
        prepare()
        if keySource == .none {
            entries = []
            snapshot = nil
            cache.clear()
            state = .noKey
        } else {
            Task { await refresh() }
        }
    }

    private func load() async {
        prepare()
        if case .denied = storedKey, detectedKey == nil {
            state = .keychainDenied
            return
        }
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
            var pricedModelIDs = snapshot?.pricedModelIDs
            if snapshot?.needsPriceRefresh(for: models) ?? true {
                // Prices are optional: without them the list is still useful, and nil dates retry next time.
                if let full = try? await client.costMap() {
                    prices = ModelCatalog.prune(full, for: models)
                    pricesFetchedAt = Date()
                    pricedModelIDs = models.map(\.id)
                }
            }
            let fresh = CatalogSnapshot(models: models, prices: prices, modelsFetchedAt: Date(),
                                        pricesFetchedAt: pricesFetchedAt, pricedModelIDs: pricedModelIDs)
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

    private var detectedKey: String? {
        APIKeyLocator.detect(home: FileManager.default.homeDirectoryForCurrentUser,
                             environment: ProcessInfo.processInfo.environment)
    }

    private var effectiveKey: String? {
        if case .found(let key) = storedKey { return key }
        return detectedKey
    }

    private func rebuild() {
        guard let snapshot else { return }
        entries = ModelCatalog.build(models: snapshot.models, prices: snapshot.prices, discounts: discounts)
    }
}
