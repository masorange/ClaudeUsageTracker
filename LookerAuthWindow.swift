//
//  LookerAuthWindow.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import AppKit
import WebKit
import os.log

private let logger = OSLog(subsystem: "com.claudeusage.tracker", category: "LookerAuth")

class LookerWebBridge: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var onDataFetched: ((LookerStudioManager.LookerDashboardData) -> Void)?
    private var onDismiss: (() -> Void)?
    private var onError: ((String) -> Void)?
    private var dataFetched = false
    private var isBackgroundMode = false

    private let reportURL = "https://lookerstudio.google.com/u/0/reporting/e666c0ca-6232-49e7-bf0b-56d05d380ff1/page/MXPqF"
    private let apiURL = "https://lookerstudio.google.com/u/0/batchedDataV2?appVersion=20260215_1001"

    private let reportId = "e666c0ca-6232-49e7-bf0b-56d05d380ff1"
    private let pageId = "83950554"
    private let datasourceId = "bfb25f28-1f01-4179-a325-8a8c42e4b881"

    private let messageHandlerName = "lookerBridge"

    // Collect all intercepted API responses before processing
    private var interceptedResponses: [[String: Any]] = []
    private var interceptTimer: Timer?
    // Store intercepted model/history data while waiting for custom API KPIs
    private var pendingResult: LookerStudioManager.LookerDashboardData?

    func show(onDataFetched: @escaping (LookerStudioManager.LookerDashboardData) -> Void, onDismiss: @escaping () -> Void) {
        self.onDataFetched = onDataFetched
        self.onDismiss = onDismiss
        self.dataFetched = false
        self.isBackgroundMode = false

        os_log("Starting LookerWebBridge (interactive)", log: logger, type: .default)

        let webView = createWebView()
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connect to Looker Studio"
        window.center()
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let url = URL(string: reportURL) {
            webView.load(URLRequest(url: url))
        }
    }

    func refreshInBackground(onDataFetched: @escaping (LookerStudioManager.LookerDashboardData) -> Void, onError: @escaping (String) -> Void) {
        self.dataFetched = false
        self.isBackgroundMode = true
        self.onDataFetched = onDataFetched
        self.onError = onError
        self.onDismiss = { onError("Session expired - please reconnect") }

        os_log("Starting background refresh", log: logger, type: .default)

        let webView = createWebView()
        self.webView = webView

        if let url = URL(string: reportURL) {
            webView.load(URLRequest(url: url))
        }
    }

    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let contentController = WKUserContentController()
        contentController.add(self, name: messageHandlerName)

        // Inject fetch interceptor BEFORE any page scripts run
        let interceptScript = WKUserScript(
            source: fetchInterceptorJS(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(interceptScript)

        config.userContentController = contentController

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
        return webView
    }

    // MARK: - Fetch Interceptor

    private func fetchInterceptorJS() -> String {
        return """
        (function() {
            var handler = window.webkit.messageHandlers.\(messageHandlerName);

            // Intercept fetch()
            var originalFetch = window.fetch;
            window.fetch = function() {
                var url = (typeof arguments[0] === 'string') ? arguments[0] : (arguments[0].url || '');
                if (url.indexOf('batchedDataV2') !== -1) {
                    return originalFetch.apply(this, arguments).then(function(response) {
                        var cloned = response.clone();
                        cloned.text().then(function(text) {
                            if (text.startsWith(")]}'")) text = text.substring(4);
                            try {
                                handler.postMessage(JSON.stringify({type: 'batchedData', response: JSON.parse(text)}));
                            } catch(e) {}
                        });
                        return response;
                    });
                }
                return originalFetch.apply(this, arguments);
            };

            // Intercept XMLHttpRequest
            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;

            XMLHttpRequest.prototype.open = function(method, url) {
                this._lookerURL = url;
                return origOpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function() {
                if (this._lookerURL && this._lookerURL.indexOf('batchedDataV2') !== -1) {
                    this.addEventListener('load', function() {
                        try {
                            var text = this.responseText;
                            if (text.startsWith(")]}'")) text = text.substring(4);
                            handler.postMessage(JSON.stringify({type: 'batchedData', response: JSON.parse(text)}));
                        } catch(e) {}
                    });
                }
                return origSend.apply(this, arguments);
            };

            handler.postMessage(JSON.stringify({type: 'interceptorReady'}));
        })();
        """
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName else { return }
        guard let body = message.body as? String,
              let jsonData = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }

        let messageType = parsed["type"] as? String ?? ""

        if messageType == "interceptorReady" {
            os_log("Fetch/XHR interceptor installed successfully", log: logger, type: .default)
            return
        }

        if messageType == "error" {
            os_log("Intercept error: %{public}@", log: logger, type: .error, parsed["error"] as? String ?? "unknown")
            return
        }

        if messageType == "customResult" {
            if let errorMsg = parsed["error"] as? String {
                os_log("Custom API error: %{public}@", log: logger, type: .error, errorMsg)
                // If we have pending intercepted data, deliver it even if custom API fails
                if let pending = pendingResult {
                    os_log("Using intercepted data despite custom API error", log: logger, type: .default)
                    dataFetched = true
                    DispatchQueue.main.async {
                        self.onDataFetched?(pending)
                        self.cleanup()
                    }
                    return
                }
                if isBackgroundMode { onError?(errorMsg) }
                return
            }
            var data = LookerStudioManager.LookerDashboardData(
                totalSpend: parsed["totalSpend"] as? Double ?? 0,
                totalTokens: parsed["totalTokens"] as? Int ?? 0,
                monthlySpend: parsed["monthlySpend"] as? Double ?? 0,
                monthlyTokens: parsed["monthlyTokens"] as? Int ?? 0,
                prevMonthSpend: parsed["prevMonthSpend"] as? Double ?? 0,
                prevMonthTokens: parsed["prevMonthTokens"] as? Int ?? 0
            )
            // Merge with intercepted model/history data if available
            if let pending = pendingResult {
                data.modelBreakdown = pending.modelBreakdown
                data.monthlyHistory = pending.monthlyHistory
                os_log("Merged custom KPIs (total=%.2f, monthly=%.2f) with intercepted data (models=%d, months=%d)",
                       log: logger, type: .default,
                       data.totalSpend, data.monthlySpend, data.modelBreakdown.count, data.monthlyHistory.count)
            }
            dataFetched = true
            DispatchQueue.main.async {
                self.onDataFetched?(data)
                self.cleanup()
            }
            return
        }

        if messageType == "batchedData" {
            guard let response = parsed["response"] as? [String: Any],
                  let dataResponse = response["dataResponse"] as? [[String: Any]] else {
                return
            }

            os_log("Intercepted batchedDataV2 with %d data responses", log: logger, type: .default, dataResponse.count)

            // Collect all responses
            interceptedResponses.append(contentsOf: dataResponse)

            // Reset timer - wait for all batches to arrive (page sends multiple)
            interceptTimer?.invalidate()
            interceptTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.processAllInterceptedData()
            }
        }
    }

    // MARK: - Data Processing

    private func processAllInterceptedData() {
        guard !dataFetched, pendingResult == nil, !interceptedResponses.isEmpty else { return }

        os_log("Processing %d intercepted responses", log: logger, type: .default, interceptedResponses.count)

        var result = LookerStudioManager.LookerDashboardData()

        // Collect all single-value KPIs with their response index for debugging
        var allDoubleKPIs: [(index: Int, value: Double)] = []
        var allLongKPIs: [(index: Int, value: Int)] = []
        var allStringKPIs: [String] = []

        // Daily history data from 3-column responses
        var dailySpendByModel: [(date: (year: Int, month: Int, day: Int), model: String, spend: Double)] = []
        var dailyTokens: [(date: (year: Int, month: Int, day: Int), tokens: Int)] = []

        var debugLines: [String] = []

        for (idx, response) in interceptedResponses.enumerated() {
            guard let dataSubsets = response["dataSubset"] as? [[String: Any]],
                  let firstSubset = dataSubsets.first,
                  let dataset = firstSubset["dataset"] as? [String: Any],
                  let tableDataset = dataset["tableDataset"] as? [String: Any],
                  let columns = tableDataset["column"] as? [[String: Any]] else {
                debugLines.append("[\(idx)]: no columns")
                continue
            }

            let colTypes = columns.map { col -> String in
                col.keys.filter { $0 != "nullIndex" }.first ?? "?"
            }

            debugLines.append("[\(idx)]: \(columns.count) cols [\(colTypes.joined(separator: ","))]")

            // === SINGLE VALUE KPIs ===
            if columns.count == 1 {
                if let val = extractDoubleValue(from: columns.first) {
                    allDoubleKPIs.append((index: idx, value: val))
                    debugLines.append("  -> dbl KPI: \(String(format: "%.2f", val))")
                } else if let val = extractLongValue(from: columns.first) {
                    allLongKPIs.append((index: idx, value: val))
                    debugLines.append("  -> long KPI: \(val)")
                } else if let strValues = extractStringArray(from: columns.first),
                          let strVal = strValues.first, !strVal.isEmpty {
                    allStringKPIs.append(strVal)
                    debugLines.append("  -> str KPI: \(strVal)")
                } else {
                    debugLines.append("  -> unknown single col")
                }
                continue
            }

            // === 3-COLUMN: dateColumn + stringColumn + doubleColumn (daily spend per model) ===
            if columns.count == 3 && colTypes.contains("dateColumn") && colTypes.contains("stringColumn") && colTypes.contains("doubleColumn") {
                let dateCol = columns.first(where: { $0["dateColumn"] != nil })
                let strCol = columns.first(where: { $0["stringColumn"] != nil })
                let dblCol = columns.first(where: { $0["doubleColumn"] != nil })

                if let dates = extractDateArrayWithDay(from: dateCol),
                   let models = extractStringArray(from: strCol),
                   let spends = extractDoubleArray(from: dblCol),
                   dates.count == models.count {

                    for (i, date) in dates.enumerated() {
                        let model = i < models.count ? models[i] : "unknown"
                        let spend = i < spends.count ? spends[i] : 0
                        dailySpendByModel.append((date: date, model: model, spend: spend))
                    }
                    debugLines.append("  -> daily model history: \(dates.count) entries")
                    continue
                }
            }

            // === 3-COLUMN: dateColumn + doubleColumn + longColumn (daily spend + tokens) ===
            if columns.count == 3 && colTypes.contains("dateColumn") && colTypes.contains("doubleColumn") && colTypes.contains("longColumn") {
                let dateCol = columns.first(where: { $0["dateColumn"] != nil })
                let dblCol = columns.first(where: { $0["doubleColumn"] != nil })
                let longCol = columns.first(where: { $0["longColumn"] != nil })

                if let dates = extractDateArrayWithDay(from: dateCol),
                   let tokens = extractLongArray(from: longCol) {

                    for (i, date) in dates.enumerated() {
                        let t = i < tokens.count ? tokens[i] : 0
                        dailyTokens.append((date: date, tokens: t))
                    }
                    debugLines.append("  -> daily tokens: \(dates.count) entries")

                    // Also use the double column as daily spend if we don't have model-level data
                    if let spends = extractDoubleArray(from: dblCol), dailySpendByModel.isEmpty {
                        for (i, date) in dates.enumerated() {
                            let spend = i < spends.count ? spends[i] : 0
                            dailySpendByModel.append((date: date, model: "total", spend: spend))
                        }
                        debugLines.append("  -> also using as daily spend fallback: \(dates.count) entries")
                    }
                    continue
                }
            }

            // === 2-COLUMN: doubleColumn + doubleColumn (aggregate metric pairs) ===
            if columns.count == 2 && colTypes.filter({ $0 == "doubleColumn" }).count == 2 {
                let vals = columns.compactMap { extractDoubleValue(from: $0) }
                debugLines.append("  -> double pair: \(vals.map { String(format: "%.2f", $0) }.joined(separator: ", "))")
                // Collect them as KPIs
                for val in vals {
                    allDoubleKPIs.append((index: idx, value: val))
                }
                continue
            }

            // === 2-COLUMN: MODEL BREAKDOWN: string[] + double[] (model names + spend) ===
            if colTypes.contains("stringColumn") && colTypes.contains("doubleColumn"),
               result.modelBreakdown.isEmpty {
                let strColIdx = columns.firstIndex(where: { $0["stringColumn"] != nil })
                let dblColIdx = columns.firstIndex(where: { $0["doubleColumn"] != nil })

                if let si = strColIdx, let di = dblColIdx,
                   let names = extractStringArray(from: columns[si]),
                   let spends = extractDoubleArray(from: columns[di]) {

                    let looksLikeModels = names.contains { $0.contains("claude") || $0.contains("gpt") || $0.contains("gemini") }
                    if looksLikeModels {
                        for (i, name) in names.enumerated() {
                            let spend = i < spends.count ? spends[i] : 0
                            result.modelBreakdown.append(LookerStudioManager.ModelEntry(model: name, spend: spend))
                        }
                        debugLines.append("  -> models: \(result.modelBreakdown.map { "\($0.model)=$\(String(format: "%.2f", $0.spend))" }.joined(separator: ", "))")
                        continue
                    }
                }
            }

            // === 2-COLUMN: MONTHLY HISTORY: dateColumn + double[] (dates + spend) ===
            if colTypes.contains("dateColumn") && colTypes.contains("doubleColumn") {
                let dateCol = columns.first(where: { $0["dateColumn"] != nil })
                let dateResult = extractDateArray(from: dateCol)

                if dateResult == nil {
                    if let dc = dateCol, let dateData = dc["dateColumn"] as? [String: Any] {
                        let keys = dateData.keys.joined(separator: ",")
                        if let rawVals = dateData["values"] {
                            debugLines.append("  -> dateCol FAILED: keys=[\(keys)], valuesType=\(type(of: rawVals))")
                            if let arr = rawVals as? [Any], let first = arr.first {
                                debugLines.append("     first element type=\(type(of: first)), val=\(String(describing: first).prefix(100))")
                            }
                        } else {
                            debugLines.append("  -> dateCol FAILED: keys=[\(keys)], no 'values' key")
                        }
                    } else {
                        debugLines.append("  -> dateCol FAILED: can't extract dateColumn dict")
                    }
                    continue
                }

                let dateEntries = dateResult!

                guard let spendValues = extractDoubleArray(from: columns.first(where: { $0["doubleColumn"] != nil })) else {
                    debugLines.append("  -> dateCol OK (\(dateEntries.count) dates) but doubleCol FAILED")
                    continue
                }

                debugLines.append("  -> dates=\(dateEntries.count), spends=\(spendValues.count)")

                if dateEntries.count > 1 && dateEntries.count >= result.monthlyHistory.count {
                    var monthlyTotals: [String: Double] = [:]
                    for (i, de) in dateEntries.enumerated() {
                        let monthKey = String(format: "%04d%02d", de.year, de.month)
                        let spend = i < spendValues.count ? spendValues[i] : 0
                        monthlyTotals[monthKey, default: 0] += spend
                    }

                    let entries = monthlyTotals.sorted { $0.key < $1.key }.map {
                        LookerStudioManager.MonthlyEntry(month: $0.key, spend: $0.value)
                    }

                    let totalFromHistory = entries.reduce(0) { $0 + $1.spend }
                    if totalFromHistory > 1 {
                        result.monthlyHistory = entries
                        debugLines.append("  -> history: \(entries.map { "\($0.month)=$\(String(format: "%.2f", $0.spend))" }.joined(separator: ", "))")
                    }
                }
                continue
            }
        }

        // === Derive model breakdown from daily model history if 2-column breakdown was empty ===
        if result.modelBreakdown.isEmpty && !dailySpendByModel.isEmpty {
            var modelTotals: [String: Double] = [:]
            for entry in dailySpendByModel {
                if entry.model != "total" {
                    modelTotals[entry.model, default: 0] += entry.spend
                }
            }
            if !modelTotals.isEmpty {
                result.modelBreakdown = modelTotals
                    .sorted { $0.value > $1.value }
                    .map { LookerStudioManager.ModelEntry(model: $0.key, spend: $0.value) }
                debugLines.append("Derived models from daily history: \(result.modelBreakdown.map { "\($0.model)=$\(String(format: "%.2f", $0.spend))" }.joined(separator: ", "))")
            }
        }

        // === Derive monthly history from daily data if 2-column history was empty ===
        if result.monthlyHistory.isEmpty && !dailySpendByModel.isEmpty {
            var monthlyTotals: [String: Double] = [:]
            for entry in dailySpendByModel {
                let monthKey = String(format: "%04d%02d", entry.date.year, entry.date.month)
                monthlyTotals[monthKey, default: 0] += entry.spend
            }
            // If we have per-model data, sum might double-count; deduplicate by using daily totals
            if dailySpendByModel.contains(where: { $0.model != "total" }) {
                // Group by date and sum per-model spends for each day
                var dailyTotals: [String: Double] = [:]
                for entry in dailySpendByModel where entry.model != "total" {
                    let dayKey = String(format: "%04d%02d%02d", entry.date.year, entry.date.month, entry.date.day)
                    dailyTotals[dayKey, default: 0] += entry.spend
                }
                monthlyTotals = [:]
                for (dayKey, spend) in dailyTotals {
                    let monthKey = String(dayKey.prefix(6))
                    monthlyTotals[monthKey, default: 0] += spend
                }
            }
            let entries = monthlyTotals.sorted { $0.key < $1.key }.map {
                LookerStudioManager.MonthlyEntry(month: $0.key, spend: $0.value)
            }
            if entries.reduce(0, { $0 + $1.spend }) > 1 {
                result.monthlyHistory = entries
                debugLines.append("Derived history from daily data: \(entries.map { "\($0.month)=$\(String(format: "%.2f", $0.spend))" }.joined(separator: ", "))")
            }
        }

        // === Populate monthly tokens from daily token data ===
        if !dailyTokens.isEmpty {
            var monthlyTokenTotals: [String: Int] = [:]
            for entry in dailyTokens {
                let monthKey = String(format: "%04d%02d", entry.date.year, entry.date.month)
                monthlyTokenTotals[monthKey, default: 0] += entry.tokens
            }
            // Enrich monthly history entries with token counts
            for i in result.monthlyHistory.indices {
                if let tokens = monthlyTokenTotals[result.monthlyHistory[i].month] {
                    result.monthlyHistory[i].tokens = tokens
                }
            }
            debugLines.append("Enriched history with tokens: \(monthlyTokenTotals.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        }

        // Log debug info
        let debugSummary = debugLines.joined(separator: "\n")
        os_log("Response details:\n%{public}@", log: logger, type: .error, debugSummary)

        let kpiSummary = "Doubles: \(allDoubleKPIs.map { "[#\($0.index)]=\(String(format: "%.2f", $0.value))" }.joined(separator: ", ")) | Longs: \(allLongKPIs.map { "[#\($0.index)]=\($0.value)" }.joined(separator: ", "))"
        os_log("KPIs: %{public}@", log: logger, type: .error, kpiSummary)

        // Sort doubles descending - largest is total spend, second is period spend
        let sortedDoubles = allDoubleKPIs.map { $0.value }.filter { $0 > 1 }.sorted(by: >)
        if let largest = sortedDoubles.first {
            result.totalSpend = largest
        }
        if sortedDoubles.count >= 2 {
            result.monthlySpend = sortedDoubles[1]
        }

        // Sort longs descending - largest is total tokens, second is period tokens
        let sortedLongs = allLongKPIs.map { $0.value }.filter { $0 > 100 }.sorted(by: >)
        if let largest = sortedLongs.first {
            result.totalTokens = largest
        }
        if sortedLongs.count >= 2 {
            result.monthlyTokens = sortedLongs[1]
        }

        // === Derive monthly KPIs from daily data (preferred over custom API) ===
        let currentMonthKey = getCurrentMonthKey()
        let prevMonthKey = getPreviousMonthKey()

        if !result.monthlyHistory.isEmpty {
            let currentMonthSpend = result.monthlyHistory
                .filter { $0.month == currentMonthKey }
                .reduce(0) { $0 + $1.spend }
            if currentMonthSpend > 0 {
                result.monthlySpend = currentMonthSpend
            }

            let prevMonthSpend = result.monthlyHistory
                .filter { $0.month == prevMonthKey }
                .reduce(0) { $0 + $1.spend }
            if prevMonthSpend > 0 {
                result.prevMonthSpend = prevMonthSpend
            }
        }

        if !dailyTokens.isEmpty {
            let currentMonthTokens = dailyTokens
                .filter { String(format: "%04d%02d", $0.date.year, $0.date.month) == currentMonthKey }
                .reduce(0) { $0 + $1.tokens }
            if currentMonthTokens > 0 {
                result.monthlyTokens = currentMonthTokens
            }

            let prevMonthTokens = dailyTokens
                .filter { String(format: "%04d%02d", $0.date.year, $0.date.month) == prevMonthKey }
                .reduce(0) { $0 + $1.tokens }
            if prevMonthTokens > 0 {
                result.prevMonthTokens = prevMonthTokens
            }
        }

        // === Identify team from single string KPIs ===
        if !allStringKPIs.isEmpty {
            debugLines.append("String KPIs: \(allStringKPIs)")
            // Team: contains dash or tier keyword, is NOT an email, is NOT a full name (has spaces)
            for str in allStringKPIs {
                let isEmail = str.contains("@")
                let hasTierKeyword = ["iron", "bronze", "silver", "gold"].contains(where: { str.lowercased().contains($0) })
                let hasDash = str.contains("-")
                let hasSpace = str.contains(" ")
                if !isEmail && (hasTierKeyword || (hasDash && !hasSpace)) {
                    result.team = str
                    debugLines.append("  -> team: \(str)")
                    break
                }
            }
        }

        os_log("Intercepted: totalSpend=%.2f, monthlySpend=%.2f, prevMonthSpend=%.2f, totalTokens=%d, monthlyTokens=%d, models=%d, months=%d, team=%{public}@",
               log: logger, type: .default,
               result.totalSpend, result.monthlySpend, result.prevMonthSpend, result.totalTokens, result.monthlyTokens,
               result.modelBreakdown.count, result.monthlyHistory.count, result.team)

        // Determine if we have enough data to skip the custom API
        let hasSpendKPIs = result.totalSpend > 0 && result.monthlySpend > 0
        let hasDetailData = !result.modelBreakdown.isEmpty || !result.monthlyHistory.isEmpty

        if hasSpendKPIs && hasDetailData {
            // We have everything we need - deliver directly without custom API
            os_log("Sufficient data from interceptor, skipping custom API", log: logger, type: .default)
            dataFetched = true
            DispatchQueue.main.async {
                self.onDataFetched?(result)
                self.cleanup()
            }
        } else if hasDetailData {
            // Have models/history but missing some KPIs - still deliver what we have
            // rather than depending on custom API with potentially stale component IDs
            os_log("Partial KPIs but have detail data, delivering without custom API", log: logger, type: .default)
            dataFetched = true
            DispatchQueue.main.async {
                self.onDataFetched?(result)
                self.cleanup()
            }
        } else if result.totalSpend > 0 {
            // No detail data but have KPIs - deliver as-is
            dataFetched = true
            DispatchQueue.main.async {
                self.onDataFetched?(result)
                self.cleanup()
            }
        } else {
            // No useful data at all - fall back to custom API as last resort
            os_log("No meaningful data from interceptor, falling back to custom API", log: logger, type: .default)
            executeCustomAPIFetch()
        }
    }

    private func getCurrentMonthKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        return formatter.string(from: Date())
    }

    private func getPreviousMonthKey() -> String {
        let calendar = Calendar.current
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        return formatter.string(from: prevMonth)
    }

    // MARK: - Value Extraction Helpers

    /// Extract a single Double from a single-value doubleColumn
    private func extractDoubleValue(from column: [String: Any]?) -> Double? {
        guard let col = column,
              let doubleCol = col["doubleColumn"] as? [String: Any],
              let rawValues = doubleCol["values"] else { return nil }

        // Direct cast
        if let values = rawValues as? [Double], let first = values.first {
            return first
        }
        // Handle NSNumber / mixed types
        if let arr = rawValues as? [Any], let first = arr.first {
            if let d = first as? Double { return d }
            if let n = first as? NSNumber { return n.doubleValue }
        }
        return nil
    }

    /// Extract a single Int from a single-value longColumn
    private func extractLongValue(from column: [String: Any]?) -> Int? {
        guard let col = column,
              let longCol = col["longColumn"] as? [String: Any],
              let rawValues = longCol["values"] else { return nil }

        // longColumn values are typically strings in Looker API
        if let values = rawValues as? [String], let first = values.first {
            return Int(first)
        }
        // Handle numeric values
        if let arr = rawValues as? [Any], let first = arr.first {
            if let n = first as? NSNumber { return n.intValue }
            if let s = first as? String { return Int(s) }
        }
        return nil
    }

    /// Extract an array of Doubles from a doubleColumn, handling nulls
    private func extractDoubleArray(from column: [String: Any]?) -> [Double]? {
        guard let col = column,
              let doubleCol = col["doubleColumn"] as? [String: Any],
              let rawValues = doubleCol["values"] else { return nil }

        if let values = rawValues as? [Double] {
            return values
        }
        // Handle array with potential NSNull or NSNumber values
        if let arr = rawValues as? [Any] {
            return arr.map { item -> Double in
                if let d = item as? Double { return d }
                if let n = item as? NSNumber { return n.doubleValue }
                return 0.0
            }
        }
        return nil
    }

    /// Extract an array of Ints from a longColumn
    private func extractLongArray(from column: [String: Any]?) -> [Int]? {
        guard let col = column,
              let longCol = col["longColumn"] as? [String: Any],
              let rawValues = longCol["values"] else { return nil }

        if let values = rawValues as? [String] {
            return values.map { Int($0) ?? 0 }
        }
        if let arr = rawValues as? [Any] {
            return arr.map { item -> Int in
                if let n = item as? NSNumber { return n.intValue }
                if let s = item as? String { return Int(s) ?? 0 }
                if let i = item as? Int { return i }
                return 0
            }
        }
        return nil
    }

    /// Extract an array of Strings from a stringColumn
    private func extractStringArray(from column: [String: Any]?) -> [String]? {
        guard let col = column,
              let strCol = col["stringColumn"] as? [String: Any],
              let rawValues = strCol["values"] else { return nil }

        if let values = rawValues as? [String] {
            return values
        }
        if let arr = rawValues as? [Any] {
            return arr.compactMap { $0 as? String }
        }
        return nil
    }

    /// Extract date entries from a dateColumn, handling multiple formats
    private func extractDateArray(from column: [String: Any]?) -> [(year: Int, month: Int)]? {
        guard let col = column,
              let dateCol = col["dateColumn"] as? [String: Any],
              let rawValues = dateCol["values"] else {
            os_log("  extractDateArray: no dateColumn or values key", log: logger, type: .default)
            return nil
        }

        os_log("  dateValues type: %{public}@", log: logger, type: .default, String(describing: type(of: rawValues)))

        // Format 1: Array of dictionaries [{"year": 2026, "month": 1, "day": 1}, ...]
        if let values = rawValues as? [[String: Any]] {
            os_log("  dateValues parsed as [[String:Any]], count=%d", log: logger, type: .default, values.count)
            return values.compactMap { dv -> (year: Int, month: Int)? in
                let year = asInt(dv["year"]) ?? 0
                let month = asInt(dv["month"]) ?? 0
                guard year > 0 else { return nil }
                return (year: year, month: month)
            }
        }

        // Format 2: Array with mixed types (some NSNull for null-indexed entries)
        if let arr = rawValues as? [Any] {
            os_log("  dateValues parsed as [Any], count=%d, first type=%{public}@", log: logger, type: .default,
                   arr.count, arr.first.map { String(describing: type(of: $0)) } ?? "nil")
            let entries = arr.compactMap { item -> (year: Int, month: Int)? in
                guard let dict = item as? [String: Any] else { return nil }
                let year = asInt(dict["year"]) ?? 0
                let month = asInt(dict["month"]) ?? 0
                guard year > 0 else { return nil }
                return (year: year, month: month)
            }
            if !entries.isEmpty { return entries }
        }

        // Format 3: Array of date strings (various formats)
        if let strings = rawValues as? [String] {
            os_log("  dateValues parsed as [String], count=%d, vals=%{public}@", log: logger, type: .default,
                   strings.count, strings.prefix(5).joined(separator: "|"))
            let entries = strings.compactMap { str -> (year: Int, month: Int)? in
                // Try "YYYY-MM-DD" or "YYYY/MM/DD" format
                let parts = str.split(whereSeparator: { $0 == "-" || $0 == "/" })
                if parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) {
                    return (year: year, month: month)
                }
                // Try "YYYYMMDD" or "YYYYMM" compact format
                if str.count >= 6, let year = Int(str.prefix(4)), let month = Int(str.dropFirst(4).prefix(2)) {
                    return (year: year, month: month)
                }
                return nil
            }
            if !entries.isEmpty { return entries }
        }

        os_log("  dateValues: no format matched", log: logger, type: .default)
        return nil
    }

    /// Extract date entries with day from a dateColumn
    private func extractDateArrayWithDay(from column: [String: Any]?) -> [(year: Int, month: Int, day: Int)]? {
        guard let col = column,
              let dateCol = col["dateColumn"] as? [String: Any],
              let rawValues = dateCol["values"] else { return nil }

        // Format 1: Array of dictionaries [{"year": 2026, "month": 1, "day": 15}, ...]
        if let values = rawValues as? [[String: Any]] {
            let entries = values.compactMap { dv -> (year: Int, month: Int, day: Int)? in
                let year = asInt(dv["year"]) ?? 0
                let month = asInt(dv["month"]) ?? 0
                let day = asInt(dv["day"]) ?? 1
                guard year > 0 else { return nil }
                return (year: year, month: month, day: day)
            }
            if !entries.isEmpty { return entries }
        }

        // Format 2: Array with mixed types
        if let arr = rawValues as? [Any] {
            let entries = arr.compactMap { item -> (year: Int, month: Int, day: Int)? in
                guard let dict = item as? [String: Any] else { return nil }
                let year = asInt(dict["year"]) ?? 0
                let month = asInt(dict["month"]) ?? 0
                let day = asInt(dict["day"]) ?? 1
                guard year > 0 else { return nil }
                return (year: year, month: month, day: day)
            }
            if !entries.isEmpty { return entries }
        }

        // Format 3: Date strings
        if let strings = rawValues as? [String] {
            let entries = strings.compactMap { str -> (year: Int, month: Int, day: Int)? in
                let parts = str.split(whereSeparator: { $0 == "-" || $0 == "/" })
                if parts.count >= 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
                    return (year: year, month: month, day: day)
                }
                if str.count >= 8, let year = Int(str.prefix(4)), let month = Int(str.dropFirst(4).prefix(2)), let day = Int(str.dropFirst(6).prefix(2)) {
                    return (year: year, month: month, day: day)
                }
                return nil
            }
            if !entries.isEmpty { return entries }
        }

        return nil
    }

    /// Safely convert Any? to Int (handles NSNumber, Int, Double, String)
    private func asInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }

    // MARK: - Fallback Custom API Call

    private func executeCustomAPIFetch() {
        guard let webView = webView, !dataFetched else { return }

        os_log("Executing custom API fetch as fallback", log: logger, type: .default)

        let requestBody = buildRequestBodyJSON()

        let js = """
        (function() {
            var xsrfToken = '';
            var cookies = document.cookie.split('; ');
            for (var i = 0; i < cookies.length; i++) {
                var parts = cookies[i].split('=');
                if (parts[0] === 'RAP_XSRF_TOKEN') {
                    xsrfToken = parts.slice(1).join('=');
                    break;
                }
            }

            if (!xsrfToken) {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage(JSON.stringify({type: 'customResult', error: 'No XSRF token'}));
                return;
            }

            fetch('\(apiURL)', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'x-rap-xsrf-token': xsrfToken
                },
                credentials: 'include',
                body: \(requestBody)
            })
            .then(function(r) { return r.text(); })
            .then(function(text) {
                if (text.startsWith(")]}'")) text = text.substring(4);
                var data = JSON.parse(text);
                var result = {type: 'customResult', totalSpend: 0, totalTokens: 0, monthlySpend: 0, monthlyTokens: 0, prevMonthSpend: 0, prevMonthTokens: 0};
                if (data.dataResponse) {
                    for (var i = 0; i < data.dataResponse.length; i++) {
                        var resp = data.dataResponse[i];
                        if (resp.dataSubset && resp.dataSubset[0] && resp.dataSubset[0].dataset) {
                            var ds = resp.dataSubset[0].dataset;
                            if (ds.tableDataset && ds.tableDataset.column && ds.tableDataset.column[0]) {
                                var col = ds.tableDataset.column[0];
                                if (col.doubleColumn && col.doubleColumn.values) {
                                    var val = col.doubleColumn.values[0];
                                    if (i === 0) result.totalSpend = val;
                                    else if (i === 2) result.monthlySpend = val;
                                    else if (i === 4) result.prevMonthSpend = val;
                                } else if (col.longColumn && col.longColumn.values) {
                                    var val = parseInt(col.longColumn.values[0]);
                                    if (i === 1) result.totalTokens = val;
                                    else if (i === 3) result.monthlyTokens = val;
                                    else if (i === 5) result.prevMonthTokens = val;
                                }
                            }
                        }
                    }
                }
                window.webkit.messageHandlers.\(messageHandlerName).postMessage(JSON.stringify(result));
            })
            .catch(function(e) {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage(JSON.stringify({type: 'customResult', error: e.message}));
            });
        })();
        """

        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                os_log("Custom fetch JS error: %{public}@", log: logger, type: .error, error.localizedDescription)
            }
        }
    }

    private func buildRequestBodyJSON() -> String {
        let calendar = Calendar.current
        let today = Date()
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let startDate = dateFormatter.string(from: firstOfMonth)
        let endDate = dateFormatter.string(from: today)

        // Previous month range
        let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth)!
        let lastDayOfPrevMonth = calendar.date(byAdding: .day, value: -1, to: firstOfMonth)!
        let prevStartDate = dateFormatter.string(from: prevMonth)
        let prevEndDate = dateFormatter.string(from: lastDayOfPrevMonth)

        // [0] totalSpend: no date filter (all-time historical)
        // [1] totalTokens: no date filter
        // [2] monthlySpend: 1st of month → today
        // [3] monthlyTokens: 1st of month → today
        // [4] prevMonthSpend: 1st of prev month → last day of prev month
        // [5] prevMonthTokens: 1st of prev month → last day of prev month
        return """
        JSON.stringify({
            "dataRequest": [
                \(metricJSON(componentId: "cd-r6i2nava1d", fieldName: "_spend_usd_", queryFieldName: "qt_t6i2nava1d")),
                \(metricJSON(componentId: "cd-ax9yvbva1d", fieldName: "_total_tokens_", queryFieldName: "qt_bx9yvbva1d")),
                \(metricJSON(componentId: "cd-c43rdlva1d", fieldName: "_spend_usd_", queryFieldName: "qt_d43rdlva1d", startDate: startDate, endDate: endDate, dateFieldName: "qt_ui0dtmva1d")),
                \(metricJSON(componentId: "cd-0begjlva1d", fieldName: "_total_tokens_", queryFieldName: "qt_1begjlva1d", startDate: startDate, endDate: endDate, dateFieldName: "qt_mgozvmva1d")),
                \(metricJSON(componentId: "cd-c43rdlva1d", fieldName: "_spend_usd_", queryFieldName: "qt_d43rdlva1d", startDate: prevStartDate, endDate: prevEndDate, dateFieldName: "qt_ui0dtmva1d")),
                \(metricJSON(componentId: "cd-0begjlva1d", fieldName: "_total_tokens_", queryFieldName: "qt_1begjlva1d", startDate: prevStartDate, endDate: prevEndDate, dateFieldName: "qt_mgozvmva1d"))
            ]
        })
        """
    }

    private func metricJSON(componentId: String, fieldName: String, queryFieldName: String, startDate: String? = nil, endDate: String? = nil, dateFieldName: String? = nil) -> String {
        let dateRangesJSON: String
        let dateRangeDimensionsJSON: String

        if let start = startDate, let end = endDate, let dfn = dateFieldName {
            dateRangesJSON = "[{\"startDate\": \(start), \"endDate\": \(end), \"dataSubsetNs\": {\"datasetNs\": \"d0\", \"tableNs\": \"t0\", \"contextNs\": \"c0\"}}]"
            dateRangeDimensionsJSON = ", \"dateRangeDimensions\": [{\"name\": \"\(dfn)\", \"datasetNs\": \"d0\", \"tableNs\": \"t0\", \"dataTransformation\": {\"sourceFieldName\": \"_fecha_\"}}]"
        } else {
            dateRangesJSON = "[]"
            dateRangeDimensionsJSON = ""
        }

        return """
        {
            "requestContext": {"reportContext": {"reportId": "\(reportId)", "pageId": "\(pageId)", "mode": 1, "componentId": "\(componentId)", "displayType": "kpi-metric"}, "requestMode": 0},
            "datasetSpec": {
                "dataset": [{"datasourceId": "\(datasourceId)", "revisionNumber": 0, "parameterOverrides": []}],
                "queryFields": [{"name": "\(queryFieldName)", "datasetNs": "d0", "tableNs": "t0", "dataTransformation": {"sourceFieldName": "\(fieldName)", "aggregation": 6}}],
                "sortData": [], "includeRowsCount": false,
                "relatedDimensionMask": {"addDisplay": false, "addUniqueId": false, "addLatLong": false},
                "dateRanges": \(dateRangesJSON)\(dateRangeDimensionsJSON),
                "dsFilterOverrides": [], "filters": [], "features": [],
                "contextNsCount": 1, "calculatedField": [],
                "needGeocoding": false, "geoFieldMask": [], "multipleGeocodeFields": [],
                "timezone": "Europe/Madrid"
            },
            "role": "main",
            "retryHints": {"useClientControlledRetry": true, "isLastRetry": false, "retryCount": 0, "originalRequestId": "\(componentId)_0_0"}
        }
        """
    }

    private func cleanup() {
        interceptTimer?.invalidate()
        interceptTimer = nil
        if !isBackgroundMode {
            window?.close()
        }
        window = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
        webView = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let currentURL = webView.url?.absoluteString ?? "unknown"
        os_log("Page loaded: %{public}@", log: logger, type: .default, currentURL)

        // If on Looker Studio and no intercepts after 8s, fallback to custom API call
        if let host = webView.url?.host, host.contains("lookerstudio.google.com"), !dataFetched {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                guard let self = self, !self.dataFetched, self.interceptedResponses.isEmpty else { return }
                os_log("No intercepted data after 8s, falling back to custom API call", log: logger, type: .default)
                self.executeCustomAPIFetch()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension LookerWebBridge: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        interceptTimer?.invalidate()
        if !dataFetched {
            onDismiss?()
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: messageHandlerName)
        webView = nil
    }
}
