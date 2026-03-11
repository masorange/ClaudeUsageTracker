//
//  LookerStudioManager.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import Foundation

extension Notification.Name {
    static let lookerDataUpdated = Notification.Name("lookerDataUpdated")
}

class LookerStudioManager: ObservableObject {
    @Published var isConfigured: Bool = false
    @Published var lastError: String? = nil
    @Published var totalSpend: Double = 0.0
    @Published var totalTokens: Int = 0
    @Published var monthlySpend: Double = 0.0
    @Published var monthlyTokens: Int = 0
    @Published var prevMonthSpend: Double = 0.0
    @Published var prevMonthTokens: Int = 0
    @Published var monthlyHistory: [MonthlyEntry] = []
    @Published var modelBreakdown: [ModelEntry] = []

    // Legacy cookie fields (kept for manual entry fallback)
    @Published var securePSID: String = "" {
        didSet { saveCookies() }
    }
    @Published var securePSIDTS: String = "" {
        didSet { saveCookies() }
    }

    // UserDefaults keys
    private let psidKey = "looker_secure_1psid"
    private let psidtsKey = "looker_secure_1psidts"
    private let connectedKey = "looker_connected"

    // WebBridge for background refreshes
    private var backgroundBridge: LookerWebBridge?

    init() {
        loadState()
    }

    // MARK: - State Management

    private func saveCookies() {
        UserDefaults.standard.set(securePSID, forKey: psidKey)
        UserDefaults.standard.set(securePSIDTS, forKey: psidtsKey)
        updateConfiguredState()
    }

    private func loadState() {
        securePSID = UserDefaults.standard.string(forKey: psidKey) ?? ""
        securePSIDTS = UserDefaults.standard.string(forKey: psidtsKey) ?? ""
        isConfigured = UserDefaults.standard.bool(forKey: connectedKey)
    }

    private func updateConfiguredState() {
        let configured = !securePSID.isEmpty && !securePSIDTS.isEmpty
        if configured != isConfigured {
            isConfigured = configured
            UserDefaults.standard.set(configured, forKey: connectedKey)
        }
    }

    func markConnected() {
        isConfigured = true
        UserDefaults.standard.set(true, forKey: connectedKey)
    }

    func clearConnection() {
        securePSID = ""
        securePSIDTS = ""
        isConfigured = false
        UserDefaults.standard.set(false, forKey: connectedKey)
        lastError = nil
        totalSpend = 0
        totalTokens = 0
        monthlySpend = 0
        monthlyTokens = 0
        prevMonthSpend = 0
        prevMonthTokens = 0
    }

    func hasValidCookies() -> Bool {
        return isConfigured
    }

    // MARK: - Data Update

    func updateWithData(_ data: LookerDashboardData) {
        self.totalSpend = data.totalSpend
        self.totalTokens = data.totalTokens
        self.monthlySpend = data.monthlySpend
        self.monthlyTokens = data.monthlyTokens
        self.prevMonthSpend = data.prevMonthSpend
        self.prevMonthTokens = data.prevMonthTokens
        if !data.monthlyHistory.isEmpty {
            self.monthlyHistory = data.monthlyHistory
        }
        if !data.modelBreakdown.isEmpty {
            self.modelBreakdown = data.modelBreakdown
        }
        self.lastError = nil
        NotificationCenter.default.post(name: .lookerDataUpdated, object: nil)
    }

    // MARK: - Background Refresh via WebBridge

    func refreshData() async {
        guard isConfigured else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                let bridge = LookerWebBridge()
                self.backgroundBridge = bridge

                bridge.refreshInBackground(
                    onDataFetched: { [weak self] data in
                        DispatchQueue.main.async {
                            self?.updateWithData(data)
                            self?.backgroundBridge = nil
                            continuation.resume()
                        }
                    },
                    onError: { [weak self] error in
                        DispatchQueue.main.async {
                            self?.lastError = error
                            self?.backgroundBridge = nil
                            continuation.resume()
                        }
                    }
                )
            }
        }
    }

    /// Validates connection by attempting a background data fetch
    func validateCookies() async -> Bool {
        guard isConfigured else { return false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.main.async {
                let bridge = LookerWebBridge()
                self.backgroundBridge = bridge

                bridge.refreshInBackground(
                    onDataFetched: { [weak self] data in
                        DispatchQueue.main.async {
                            self?.updateWithData(data)
                            self?.backgroundBridge = nil
                            continuation.resume(returning: true)
                        }
                    },
                    onError: { [weak self] error in
                        DispatchQueue.main.async {
                            self?.lastError = error
                            self?.backgroundBridge = nil
                            continuation.resume(returning: false)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Data Structures

    struct LookerDashboardData {
        var totalSpend: Double = 0.0
        var totalTokens: Int = 0
        var monthlySpend: Double = 0.0
        var monthlyTokens: Int = 0
        var prevMonthSpend: Double = 0.0
        var prevMonthTokens: Int = 0
        var monthlyHistory: [MonthlyEntry] = []
        var modelBreakdown: [ModelEntry] = []
    }

    struct MonthlyEntry {
        var month: String  // YYYYMM format
        var spend: Double = 0.0
        var tokens: Int = 0
    }

    struct ModelEntry {
        var model: String
        var spend: Double = 0.0
        var tokens: Int = 0
    }
}
