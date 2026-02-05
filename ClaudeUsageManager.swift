//
//  ClaudeUsageManager.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import Foundation

class ClaudeUsageManager: ObservableObject {
    @Published var monthlyData: [(month: String, cost: Double, details: TokenBreakdown)] = []
    @Published var projectData: [(project: String, cost: Double, details: TokenBreakdown)] = []
    @Published var modelData: [(model: String, cost: Double, details: TokenBreakdown)] = []
    @Published var currentMonthCost: Double = 0.0
    @Published var totalCost: Double = 0.0
    @Published var lastUpdate: Date = Date()
    @Published var isLoading: Bool = false
    @Published var dataSource: DataSource = .local

    enum DataSource {
        case api
        case local
    }

    var onDataUpdated: (() -> Void)?
    var onLoadingStateChanged: ((Bool) -> Void)?
    var pricingManager: PricingManager?
    var localizationManager: LocalizationManager?
    var liteLLMManager: LiteLLMManager?
    var accountFilter: AccountFilter = .all

    // Reusable date formatter (creating these is expensive)
    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Cache for file modification dates to avoid re-processing unchanged files
    private var fileModificationCache: [String: Date] = [:]
    // Cache for processed file results
    private var fileResultsCache: [String: (monthlyData: [String: TokenBreakdown], projectBreakdown: TokenBreakdown, modelData: [String: TokenBreakdown])] = [:]
    // Track last account filter to invalidate cache when it changes
    private var lastAccountFilter: AccountFilter = .all
    
    struct TokenBreakdown {
        var inputTokens: Int = 0
        var cacheCreationTokens: Int = 0
        var cacheReadTokens: Int = 0
        var outputTokens: Int = 0
        var maxContextSize: Int = 0 // Maximum context size of any single message (for reference only)
        var accumulatedCost: Double = 0.0 // Cost calculated message by message with correct pricing tier

        // Estimated individual costs (used when data comes from API)
        var estimatedInputCost: Double? = nil
        var estimatedCacheCreationCost: Double? = nil
        var estimatedCacheReadCost: Double? = nil
        var estimatedOutputCost: Double? = nil
    }
    
    // Process a turn - sum ALL messages (each API request is billed separately)
    private func processTurn(_ turnMessages: [(timestamp: String?, monthKey: String?, input: Int, cacheCreation: Int, cacheRead: Int, output: Int, contextSize: Int, model: String?)],
                             monthlyDict: inout [String: TokenBreakdown],
                             projectBreakdown: inout TokenBreakdown,
                             modelDict: inout [String: TokenBreakdown]) {

        // Process ALL messages in the turn (API charges for each request)
        for message in turnMessages {
            let input = message.input
            let cacheCreation = message.cacheCreation
            let cacheRead = message.cacheRead
            let output = message.output
            let contextSize = message.contextSize
            let modelName = message.model ?? "Unknown Model"

            // Calculate cost for this message using the model's pricing
            let messageCost = calculateMessageCost(
                input: input,
                cacheCreation: cacheCreation,
                cacheRead: cacheRead,
                output: output,
                contextSize: contextSize,
                model: modelName
            )

            // Update monthly data
            if let monthKey = message.monthKey {
                var monthBreakdown = monthlyDict[monthKey] ?? TokenBreakdown()
                monthBreakdown.inputTokens += input
                monthBreakdown.cacheCreationTokens += cacheCreation
                monthBreakdown.cacheReadTokens += cacheRead
                monthBreakdown.outputTokens += output
                monthBreakdown.maxContextSize = max(monthBreakdown.maxContextSize, contextSize)
                monthBreakdown.accumulatedCost += messageCost
                monthlyDict[monthKey] = monthBreakdown
            }

            // Update project data
            projectBreakdown.inputTokens += input
            projectBreakdown.cacheCreationTokens += cacheCreation
            projectBreakdown.cacheReadTokens += cacheRead
            projectBreakdown.outputTokens += output
            projectBreakdown.maxContextSize = max(projectBreakdown.maxContextSize, contextSize)
            projectBreakdown.accumulatedCost += messageCost

            // Update model data
            var modelBreakdown = modelDict[modelName] ?? TokenBreakdown()
            modelBreakdown.inputTokens += input
            modelBreakdown.cacheCreationTokens += cacheCreation
            modelBreakdown.cacheReadTokens += cacheRead
            modelBreakdown.outputTokens += output
            modelBreakdown.maxContextSize = max(modelBreakdown.maxContextSize, contextSize)
            modelBreakdown.accumulatedCost += messageCost
            modelDict[modelName] = modelBreakdown
        }
    }

    func loadData(showLoading: Bool = true) {
        // Notificar que está cargando solo si se solicita
        if showLoading {
            DispatchQueue.main.async {
                self.isLoading = true
                self.onLoadingStateChanged?(true)
            }
        }

        // Try API first if available
        if let liteLLMManager = liteLLMManager, liteLLMManager.hasValidAPIKey() {
            Task {
                do {
                    // Fetch all API data concurrently
                    async let usageData = liteLLMManager.fetchUsageData()
                    async let userInfoTask = liteLLMManager.fetchUserInfo()
                    async let todaySpendTask = liteLLMManager.fetchTodaySpend()

                    let (apiMonthlyData, apiModelData) = try await usageData
                    try await userInfoTask
                    try await todaySpendTask

                    // Update UI with API data
                    await MainActor.run {
                        self.monthlyData = apiMonthlyData
                        self.modelData = apiModelData
                        self.dataSource = .api

                        let currentMonth = self.getCurrentMonthKey()
                        self.currentMonthCost = self.monthlyData.first(where: { $0.month == currentMonth })?.cost ?? 0.0
                        self.totalCost = self.monthlyData.reduce(0) { $0 + $1.cost }

                        print("💵 [Manager] Total Cost: $\(String(format: "%.2f", self.totalCost))")
                        print("📅 [Manager] Monthly breakdown:")
                        for month in self.monthlyData {
                            print("   \(month.month): $\(String(format: "%.2f", month.cost))")
                        }

                        // Project data still comes from local files (API doesn't provide per-project breakdown)
                        self.loadLocalProjectData()

                        self.lastUpdate = Date()

                        if showLoading {
                            self.isLoading = false
                        }

                        self.onDataUpdated?()
                    }
                } catch {
                    // API failed, fallback to local calculation
                    print("⚠️ API failed: \(error.localizedDescription). Falling back to local calculation.")
                    self.loadLocalData(showLoading: showLoading)
                }
            }
            return
        }

        // No API key or not valid, use local calculation
        loadLocalData(showLoading: showLoading)
    }

    private func loadLocalData(showLoading: Bool) {
        // Process data in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Invalidate cache if account filter changed
            if self.lastAccountFilter != self.accountFilter {
                self.fileModificationCache.removeAll()
                self.fileResultsCache.removeAll()
                self.lastAccountFilter = self.accountFilter
            }

            let claudeProjectsPath = self.getClaudeProjectsPath()

            var monthlyDict: [String: TokenBreakdown] = [:]
            var projectDict: [String: TokenBreakdown] = [:]
            var modelDict: [String: TokenBreakdown] = [:]
        
        guard let projects = try? FileManager.default.contentsOfDirectory(atPath: claudeProjectsPath.path) else {
            return
        }
        
        for project in projects {
            let projectPath = claudeProjectsPath.appendingPathComponent(project)
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: projectPath.path) else {
                continue
            }
            
            var projectBreakdown = TokenBreakdown()
            
            for file in files where file.hasSuffix(".jsonl") {
                let filePath = projectPath.appendingPathComponent(file)
                let fileKey = filePath.path

                // Check if file has been modified since last cache
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileKey),
                   let modDate = attributes[.modificationDate] as? Date {
                    if let cachedDate = self.fileModificationCache[fileKey],
                       let cachedResult = self.fileResultsCache[fileKey],
                       modDate <= cachedDate {
                        // File unchanged, use cached results
                        for (month, breakdown) in cachedResult.monthlyData {
                            var existing = monthlyDict[month] ?? TokenBreakdown()
                            existing.inputTokens += breakdown.inputTokens
                            existing.cacheCreationTokens += breakdown.cacheCreationTokens
                            existing.cacheReadTokens += breakdown.cacheReadTokens
                            existing.outputTokens += breakdown.outputTokens
                            existing.maxContextSize = max(existing.maxContextSize, breakdown.maxContextSize)
                            existing.accumulatedCost += breakdown.accumulatedCost
                            monthlyDict[month] = existing
                        }
                        projectBreakdown.inputTokens += cachedResult.projectBreakdown.inputTokens
                        projectBreakdown.cacheCreationTokens += cachedResult.projectBreakdown.cacheCreationTokens
                        projectBreakdown.cacheReadTokens += cachedResult.projectBreakdown.cacheReadTokens
                        projectBreakdown.outputTokens += cachedResult.projectBreakdown.outputTokens
                        projectBreakdown.maxContextSize = max(projectBreakdown.maxContextSize, cachedResult.projectBreakdown.maxContextSize)
                        projectBreakdown.accumulatedCost += cachedResult.projectBreakdown.accumulatedCost
                        for (model, breakdown) in cachedResult.modelData {
                            var existing = modelDict[model] ?? TokenBreakdown()
                            existing.inputTokens += breakdown.inputTokens
                            existing.cacheCreationTokens += breakdown.cacheCreationTokens
                            existing.cacheReadTokens += breakdown.cacheReadTokens
                            existing.outputTokens += breakdown.outputTokens
                            existing.maxContextSize = max(existing.maxContextSize, breakdown.maxContextSize)
                            existing.accumulatedCost += breakdown.accumulatedCost
                            modelDict[model] = existing
                        }
                        continue
                    }
                    // Update cache with new modification date
                    self.fileModificationCache[fileKey] = modDate
                }

                guard let content = try? String(contentsOf: filePath) else { continue }

                let lines = content.components(separatedBy: .newlines)

                // Local results for this file (for caching)
                var fileMonthlyDict: [String: TokenBreakdown] = [:]
                var fileProjectBreakdown = TokenBreakdown()
                var fileModelDict: [String: TokenBreakdown] = [:]

                // Track consecutive assistant messages (same turn)
                var currentTurnMessages: [(timestamp: String?, monthKey: String?, input: Int, cacheCreation: Int, cacheRead: Int, output: Int, contextSize: Int, model: String?)] = []
                var lastTimestamp: Date?

                for line in lines where !line.isEmpty {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let message = json["message"] as? [String: Any] else {
                        continue
                    }

                    // Filter by account type based on message ID prefix
                    if let messageId = message["id"] as? String {
                        let isVertexMessage = messageId.hasPrefix("msg_vrtx")
                        switch self.accountFilter {
                        case .workOnly:
                            if !isVertexMessage { continue }
                        case .personalOnly:
                            if isVertexMessage { continue }
                        case .all:
                            break
                        }
                    }

                    let role = message["role"] as? String
                    let usage = message["usage"] as? [String: Any]
                    let model = json["model"] as? String ?? (message["model"] as? String)

                    // If no usage data, this message ends the current turn
                    guard let usage = usage else {
                        // Process accumulated turn messages
                        if !currentTurnMessages.isEmpty {
                            self.processTurn(currentTurnMessages, monthlyDict: &fileMonthlyDict, projectBreakdown: &fileProjectBreakdown, modelDict: &fileModelDict)
                            currentTurnMessages.removeAll()
                        }
                        lastTimestamp = nil
                        continue
                    }

                    let input = usage["input_tokens"] as? Int ?? 0
                    let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0

                    // Cache creation - try both formats (old and new)
                    var cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
                    if cacheCreation == 0, let cacheCreationDict = usage["cache_creation"] as? [String: Any] {
                        cacheCreation = cacheCreationDict["ephemeral_5m_input_tokens"] as? Int ?? 0
                        cacheCreation += cacheCreationDict["ephemeral_1h_input_tokens"] as? Int ?? 0
                    }

                    let contextSize = input + cacheCreation + cacheRead
                    let timestamp = json["timestamp"] as? String
                    let monthKey = timestamp.map { String($0.prefix(7)) }

                    // Check if this is part of the same turn (assistant role, within 10 seconds)
                    var isNewTurn = false
                    if let timestamp = timestamp {
                        // Use reusable formatter instead of creating new one per line
                        if let currentDate = self.iso8601Formatter.date(from: timestamp) {
                            if let lastDate = lastTimestamp {
                                let timeDiff = currentDate.timeIntervalSince(lastDate)
                                // If more than 10 seconds apart or role is not assistant, start new turn
                                if timeDiff > 10 || role != "assistant" {
                                    isNewTurn = true
                                }
                            }

                            lastTimestamp = currentDate
                        } else {
                            isNewTurn = true
                        }
                    } else {
                        isNewTurn = true
                    }

                    // If new turn starts, process the previous turn
                    if isNewTurn && !currentTurnMessages.isEmpty {
                        self.processTurn(currentTurnMessages, monthlyDict: &fileMonthlyDict, projectBreakdown: &fileProjectBreakdown, modelDict: &fileModelDict)
                        currentTurnMessages.removeAll()
                    }

                    // Add current message to the turn
                    currentTurnMessages.append((
                        timestamp: timestamp,
                        monthKey: monthKey,
                        input: input,
                        cacheCreation: cacheCreation,
                        cacheRead: cacheRead,
                        output: output,
                        contextSize: contextSize,
                        model: model
                    ))
                }

                // Process any remaining turn messages at the end of file
                if !currentTurnMessages.isEmpty {
                    self.processTurn(currentTurnMessages, monthlyDict: &fileMonthlyDict, projectBreakdown: &fileProjectBreakdown, modelDict: &fileModelDict)
                }

                // Cache the results for this file
                self.fileResultsCache[fileKey] = (monthlyData: fileMonthlyDict, projectBreakdown: fileProjectBreakdown, modelData: fileModelDict)

                // Merge file results into global dictionaries
                for (month, breakdown) in fileMonthlyDict {
                    var existing = monthlyDict[month] ?? TokenBreakdown()
                    existing.inputTokens += breakdown.inputTokens
                    existing.cacheCreationTokens += breakdown.cacheCreationTokens
                    existing.cacheReadTokens += breakdown.cacheReadTokens
                    existing.outputTokens += breakdown.outputTokens
                    existing.maxContextSize = max(existing.maxContextSize, breakdown.maxContextSize)
                    existing.accumulatedCost += breakdown.accumulatedCost
                    monthlyDict[month] = existing
                }
                projectBreakdown.inputTokens += fileProjectBreakdown.inputTokens
                projectBreakdown.cacheCreationTokens += fileProjectBreakdown.cacheCreationTokens
                projectBreakdown.cacheReadTokens += fileProjectBreakdown.cacheReadTokens
                projectBreakdown.outputTokens += fileProjectBreakdown.outputTokens
                projectBreakdown.maxContextSize = max(projectBreakdown.maxContextSize, fileProjectBreakdown.maxContextSize)
                projectBreakdown.accumulatedCost += fileProjectBreakdown.accumulatedCost
                for (model, breakdown) in fileModelDict {
                    var existing = modelDict[model] ?? TokenBreakdown()
                    existing.inputTokens += breakdown.inputTokens
                    existing.cacheCreationTokens += breakdown.cacheCreationTokens
                    existing.cacheReadTokens += breakdown.cacheReadTokens
                    existing.outputTokens += breakdown.outputTokens
                    existing.maxContextSize = max(existing.maxContextSize, breakdown.maxContextSize)
                    existing.accumulatedCost += breakdown.accumulatedCost
                    modelDict[model] = existing
                }
            }
            
            if projectBreakdown.inputTokens > 0 || projectBreakdown.cacheCreationTokens > 0 ||
               projectBreakdown.cacheReadTokens > 0 || projectBreakdown.outputTokens > 0 {
                projectDict[project] = projectBreakdown
            }
        }
        
        // Convert to arrays and calculate costs
        DispatchQueue.main.async {
            self.monthlyData = monthlyDict.map { (month, breakdown) in
                let cost = self.calculateCost(breakdown)
                return (month: month, cost: cost, details: breakdown)
            }.sorted { $0.month > $1.month }

            self.projectData = projectDict.map { (project, breakdown) in
                let cost = self.calculateCost(breakdown)
                let simplifiedName = self.simplifyProjectName(project)
                return (project: simplifiedName, cost: cost, details: breakdown)
            }.sorted { $0.cost > $1.cost }
            
            self.modelData = modelDict.compactMap { (model, breakdown) in
                let cost = self.calculateCost(breakdown)
                // Only include models with actual spend
                guard cost > 0 else { return nil }
                return (model: model, cost: cost, details: breakdown)
            }.sorted { $0.cost > $1.cost }

            // Calculate current month cost
            let currentMonth = self.getCurrentMonthKey()
            self.currentMonthCost = self.monthlyData.first(where: { $0.month == currentMonth })?.cost ?? 0.0

            // Calculate total
            self.totalCost = self.monthlyData.reduce(0) { $0 + $1.cost }

            self.dataSource = .local
            self.lastUpdate = Date()

            // Finalizar carga solo si se estaba mostrando
            if showLoading {
                self.isLoading = false
            }

            // Notificar que los datos se actualizaron
            self.onDataUpdated?()
        }
        }
    }

    private func loadLocalProjectData() {
        // Load project data from cached results (files were already processed in loadLocalData)
        // This avoids re-reading and re-parsing the same JSONL files
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let claudeProjectsPath = self.getClaudeProjectsPath()

            var projectDict: [String: TokenBreakdown] = [:]

            guard let projects = try? FileManager.default.contentsOfDirectory(atPath: claudeProjectsPath.path) else {
                return
            }

            for project in projects {
                let projectPath = claudeProjectsPath.appendingPathComponent(project)
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: projectPath.path) else {
                    continue
                }

                var projectBreakdown = TokenBreakdown()

                for file in files where file.hasSuffix(".jsonl") {
                    let filePath = projectPath.appendingPathComponent(file)
                    let fileKey = filePath.path

                    // Use cached results if available
                    if let cachedResult = self.fileResultsCache[fileKey] {
                        projectBreakdown.inputTokens += cachedResult.projectBreakdown.inputTokens
                        projectBreakdown.cacheCreationTokens += cachedResult.projectBreakdown.cacheCreationTokens
                        projectBreakdown.cacheReadTokens += cachedResult.projectBreakdown.cacheReadTokens
                        projectBreakdown.outputTokens += cachedResult.projectBreakdown.outputTokens
                        projectBreakdown.maxContextSize = max(projectBreakdown.maxContextSize, cachedResult.projectBreakdown.maxContextSize)
                        projectBreakdown.accumulatedCost += cachedResult.projectBreakdown.accumulatedCost
                    }
                }

                if projectBreakdown.inputTokens > 0 || projectBreakdown.cacheCreationTokens > 0 ||
                   projectBreakdown.cacheReadTokens > 0 || projectBreakdown.outputTokens > 0 {
                    projectDict[project] = projectBreakdown
                }
            }

            DispatchQueue.main.async {
                self.projectData = projectDict.map { (project, breakdown) in
                    let cost = self.calculateCost(breakdown)
                    let simplifiedName = self.simplifyProjectName(project)
                    return (project: simplifiedName, cost: cost, details: breakdown)
                }.sorted { $0.cost > $1.cost }
            }
        }
    }
    
    private func calculateCost(_ breakdown: TokenBreakdown) -> Double {
        // Return the accumulated cost that was calculated message by message
        return breakdown.accumulatedCost
    }

    // Calculate cost for a single message based on the model used
    private func calculateMessageCost(input: Int, cacheCreation: Int, cacheRead: Int, output: Int, contextSize: Int, model: String? = nil) -> Double {
        // Get pricing based on the model used
        let modelPricing = PricingManager.getPricing(for: model ?? "claude-sonnet-4-5")

        // Convert from per-1K tokens to per-token (divide by 1000)
        let inputCost = Double(input) * (modelPricing.inputPrice / 1_000_000)
        let cacheCreationCost = Double(cacheCreation) * (modelPricing.cacheCreation / 1_000_000)
        let cacheReadCost = Double(cacheRead) * (modelPricing.cacheRead / 1_000_000)
        let outputCost = Double(output) * (modelPricing.outputPrice / 1_000_000)

        return inputCost + cacheCreationCost + cacheReadCost + outputCost
    }
    
    private func getCurrentMonthKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }
    
    private func getClaudeProjectsPath() -> URL {
        // Check if CLAUDE_CONFIG_DIR environment variable is set
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !configDir.isEmpty {
            // Handle tilde expansion
            let expandedPath = (configDir as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath).appendingPathComponent("projects")
        }

        // Fallback to default ~/.claude/projects
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    private func simplifyProjectName(_ name: String) -> String {
        // Extract the actual project name from the path
        // Format: -Users-username-Documents-PERSONAL-ProjectName or similar
        let components = name.components(separatedBy: "-")
        
        // Find the last meaningful component (after PERSONAL, Documents, etc.)
        if let personalIndex = components.lastIndex(where: { $0 == "PERSONAL" || $0 == "Documents" }) {
            let projectComponents = components.suffix(from: personalIndex + 1)
            if !projectComponents.isEmpty {
                return projectComponents.joined(separator: "-")
            }
        }
        
        // Fallback: return last component if it's not a UUID pattern
        if let lastComponent = components.last, !lastComponent.isEmpty {
            // Check if it looks like a UUID (contains numbers and letters in a specific pattern)
            let uuidPattern = #"^[0-9a-fA-F]{8}$"#
            if lastComponent.range(of: uuidPattern, options: .regularExpression) == nil {
                return lastComponent
            }
        }
        
        return name
    }
    
    func formatMonth(_ monthKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: monthKey) {
            formatter.dateFormat = "MMMM yyyy"

            // Use the current app language
            if let localizationManager = localizationManager {
                let localeIdentifier = localizationManager.currentLanguage == .english ? "en_US" : "es_ES"
                formatter.locale = Locale(identifier: localeIdentifier)
            } else {
                // Fallback to system locale if localizationManager is not set
                formatter.locale = Locale.current
            }

            return formatter.string(from: date)
        }
        return monthKey
    }
}
