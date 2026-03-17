//
//  MainView.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var manager: ClaudeUsageManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var pricingManager: PricingManager
    @EnvironmentObject var currencyManager: CurrencyManager
    @EnvironmentObject var liteLLMManager: LiteLLMManager
    @EnvironmentObject var lookerStudioManager: LookerStudioManager
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var preferencesManager: PreferencesManager
    @State private var selectedTab = 0
    @State private var showSettings = false
    @State private var showAPIBlockedNotice = false
    @State private var isReconnectingLooker = false
    @State private var showLookerPromo = false
    @State private var isConnectingFromPromo = false

    // Key for tracking if the API blocked notice has been shown (version-specific)
    private let apiBlockedNoticeKey = "api_blocked_notice_shown_v1_8"
    private let lookerPromoKey = "looker_promo_shown_v1_12"

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private var hasLookerError: Bool {
        lookerStudioManager.isConfigured && lookerStudioManager.lastError != nil
    }

    @ViewBuilder
    private var tierUsageView: some View {
        let tier = LookerStudioManager.detectTier(from: lookerStudioManager.team)

        HStack(spacing: 6) {
            // Team name
            Text(lookerStudioManager.team)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let tier = tier {
                // Tier badge
                Text(tier.name)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(tier.color.opacity(0.2))
                    .foregroundColor(tier.color == .yellow ? .orange : tier.color)
                    .cornerRadius(4)
            }

            Spacer()
        }

        if let tier = tier {
            let spent = lookerStudioManager.monthlySpend
            let limit = tier.monthlyLimit
            let ratio = min(spent / limit, 1.0)
            let barColor: Color = ratio > 0.9 ? .red : (ratio > 0.75 ? .orange : .green)

            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: max(geo.size.width * ratio, 2), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(currencyManager.formatAmount(lookerStudioManager.monthlySpend, language: localizationManager.currentLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(ratio * 100))% of \(currencyManager.formatAmount(limit, language: localizationManager.currentLanguage))")
                        .font(.caption2)
                        .foregroundColor(barColor)
                }
            }
        }
    }

    private var dataSourceColor: Color {
        if hasLookerError { return .red }
        switch manager.dataSource {
        case .api: return .green
        case .lookerStudio: return .cyan
        case .local: return .orange
        }
    }

    private var dataSourceLabel: String {
        let isEn = localizationManager.currentLanguage == .english
        if hasLookerError {
            let error = lookerStudioManager.lastError ?? ""
            if error.lowercased().contains("expired") || error.lowercased().contains("reconnect") {
                return isEn ? "Looker · Session expired" : "Looker · Sesión expirada"
            }
            return isEn ? "Looker · Connection error" : "Looker · Error de conexión"
        }
        switch manager.dataSource {
        case .api: return isEn ? "API Data" : "Datos de API"
        case .lookerStudio: return isEn ? "Looker Studio" : "Looker Studio"
        case .local: return isEn ? "Local Data" : "Datos Locales"
        }
    }

    private func checkAndShowNotice() {
        if !UserDefaults.standard.bool(forKey: lookerPromoKey) && !lookerStudioManager.isConfigured {
            showLookerPromo = true
        } else if !UserDefaults.standard.bool(forKey: apiBlockedNoticeKey) {
            showAPIBlockedNotice = true
        }
    }

    private func dismissNotice() {
        UserDefaults.standard.set(true, forKey: apiBlockedNoticeKey)
        showAPIBlockedNotice = false
    }

    private func dismissLookerPromo() {
        UserDefaults.standard.set(true, forKey: lookerPromoKey)
        showLookerPromo = false
    }

    private func connectFromPromo() {
        isConnectingFromPromo = true
        let bridge = LookerWebBridge()
        MainView.lookerBridge = bridge
        let lookerManager = lookerStudioManager

        bridge.show(
            onDataFetched: { data in
                DispatchQueue.main.async {
                    lookerManager.updateWithData(data)
                    lookerManager.markConnected()
                    self.isConnectingFromPromo = false
                    self.showLookerPromo = false
                    UserDefaults.standard.set(true, forKey: self.lookerPromoKey)
                    MainView.lookerBridge = nil
                }
            },
            onDismiss: {
                DispatchQueue.main.async {
                    self.isConnectingFromPromo = false
                    MainView.lookerBridge = nil
                }
            }
        )
    }

    private static var lookerBridge: LookerWebBridge?

    private func reconnectLooker() {
        isReconnectingLooker = true
        let bridge = LookerWebBridge()
        MainView.lookerBridge = bridge
        let lookerManager = lookerStudioManager

        bridge.show(
            onDataFetched: { data in
                DispatchQueue.main.async {
                    lookerManager.updateWithData(data)
                    lookerManager.markConnected()
                    self.isReconnectingLooker = false
                    MainView.lookerBridge = nil
                }
            },
            onDismiss: {
                DispatchQueue.main.async {
                    self.isReconnectingLooker = false
                    MainView.lookerBridge = nil
                }
            }
        )
    }

    private func dismissLookerError() {
        lookerStudioManager.lastError = nil
    }

    func formatResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: localizationManager.currentLanguage == .english ? "en_US" : "es_ES")
        return formatter.string(from: date)
    }

    func exportToCSV() {
        // Activate the app to bring the save panel to front
        NSApp.activate(ignoringOtherApps: true)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "claude_usage_export.csv"
        savePanel.level = .floating

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            var csvContent = ""

            if selectedTab == 0 {
                // Export Monthly Data
                csvContent += "Month,Token Type,Tokens,Cost ($)\n"

                for item in manager.monthlyData {
                    let formattedMonth = manager.formatMonth(item.month)

                    // Calculate costs
                    let inputCost = item.details.estimatedInputCost ?? (Double(item.details.inputTokens) * 0.000003)
                    let cacheCreationCost = item.details.estimatedCacheCreationCost ?? (Double(item.details.cacheCreationTokens) * 0.00000375)
                    let cacheReadCost = item.details.estimatedCacheReadCost ?? (Double(item.details.cacheReadTokens) * 0.0000003)
                    let outputCost = item.details.estimatedOutputCost ?? (Double(item.details.outputTokens) * 0.000015)
                    
                    let inputCostStr = String(format: "%.2f", inputCost)
                    let cacheCreationCostStr = String(format: "%.2f", cacheCreationCost)
                    let cacheReadCostStr = String(format: "%.2f", cacheReadCost)
                    let outputCostStr = String(format: "%.2f", outputCost)
                    let totalCostStr = String(format: "%.2f", item.cost)

                    csvContent += "\"\(formattedMonth)\",Input,\(item.details.inputTokens),\(inputCostStr)\n"
                    csvContent += "\"\(formattedMonth)\",Cache Creation,\(item.details.cacheCreationTokens),\(cacheCreationCostStr)\n"
                    csvContent += "\"\(formattedMonth)\",Cache Read,\(item.details.cacheReadTokens),\(cacheReadCostStr)\n"
                    csvContent += "\"\(formattedMonth)\",Output,\(item.details.outputTokens),\(outputCostStr)\n"
                    csvContent += "\"\(formattedMonth)\",TOTAL,-,\(totalCostStr)\n"
                    csvContent += "\n"
                }
                
                let grandTotalStr = String(format: "%.2f", manager.totalCost)
                csvContent += "GRAND TOTAL,-,-,\(grandTotalStr)\n"

            } else if selectedTab == 1 {
                // Export Project Data
                csvContent += "Project,Token Type,Tokens,Cost ($)\n"

                for item in manager.projectData {
                    let escapedProject = item.project

                    // Calculate costs
                    let inputCost = item.details.estimatedInputCost ?? (Double(item.details.inputTokens) * 0.000003)
                    let cacheCreationCost = item.details.estimatedCacheCreationCost ?? (Double(item.details.cacheCreationTokens) * 0.00000375)
                    let cacheReadCost = item.details.estimatedCacheReadCost ?? (Double(item.details.cacheReadTokens) * 0.0000003)
                    let outputCost = item.details.estimatedOutputCost ?? (Double(item.details.outputTokens) * 0.000015)
                    
                    let inputCostStr = String(format: "%.2f", inputCost)
                    let cacheCreationCostStr = String(format: "%.2f", cacheCreationCost)
                    let cacheReadCostStr = String(format: "%.2f", cacheReadCost)
                    let outputCostStr = String(format: "%.2f", outputCost)
                    let totalCostStr = String(format: "%.2f", item.cost)

                    csvContent += "\"\(escapedProject)\",Input,\(item.details.inputTokens),\(inputCostStr)\n"
                    csvContent += "\"\(escapedProject)\",Cache Creation,\(item.details.cacheCreationTokens),\(cacheCreationCostStr)\n"
                    csvContent += "\"\(escapedProject)\",Cache Read,\(item.details.cacheReadTokens),\(cacheReadCostStr)\n"
                    csvContent += "\"\(escapedProject)\",Output,\(item.details.outputTokens),\(outputCostStr)\n"
                    csvContent += "\"\(escapedProject)\",TOTAL,-,\(totalCostStr)\n"
                    csvContent += "\n"
                }

                let grandTotalStr = String(format: "%.2f", manager.totalCost)
                csvContent += "GRAND TOTAL,-,-,\(grandTotalStr)\n"
                
            } else {
                 // Export Model Data
                 csvContent += "Model,Token Type,Tokens,Cost ($)\n"

                 for item in manager.modelData {
                     let escapedModel = item.model

                     // Calculate costs
                     let inputCost = Double(item.details.inputTokens) * 0.000003
                     let cacheCreationCost = Double(item.details.cacheCreationTokens) * 0.00000375
                     let cacheReadCost = Double(item.details.cacheReadTokens) * 0.0000003
                     let outputCost = Double(item.details.outputTokens) * 0.000015
                     
                     let inputCostStr = String(format: "%.2f", inputCost)
                     let cacheCreationCostStr = String(format: "%.2f", cacheCreationCost)
                     let cacheReadCostStr = String(format: "%.2f", cacheReadCost)
                     let outputCostStr = String(format: "%.2f", outputCost)
                     let totalCostStr = String(format: "%.2f", item.cost)

                     csvContent += "\"\(escapedModel)\",Input,\(item.details.inputTokens),\(inputCostStr)\n"
                     csvContent += "\"\(escapedModel)\",Cache Creation,\(item.details.cacheCreationTokens),\(cacheCreationCostStr)\n"
                     csvContent += "\"\(escapedModel)\",Cache Read,\(item.details.cacheReadTokens),\(cacheReadCostStr)\n"
                     csvContent += "\"\(escapedModel)\",Output,\(item.details.outputTokens),\(outputCostStr)\n"
                     csvContent += "\"\(escapedModel)\",TOTAL,-,\(totalCostStr)\n"
                     csvContent += "\n"
                 }

                 let grandTotalStr = String(format: "%.2f", manager.totalCost)
                 csvContent += "GRAND TOTAL,-,-,\(grandTotalStr)\n"
             }

            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error saving CSV: \(error)")
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("💰 \(localizationManager.localized(.title))")
                        .font(.headline)

                    // Data source indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(dataSourceColor)
                            .frame(width: 6, height: 6)
                        Text(dataSourceLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Account filter indicator
                        if preferencesManager.accountFilter != .all {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(preferencesManager.accountFilter == .workOnly ?
                                 (localizationManager.currentLanguage == .english ? "Work" : "Trabajo") :
                                 (localizationManager.currentLanguage == .english ? "Personal" : "Personal"))
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }

                    // Toggle to hide cost in menu bar
                    Toggle(isOn: $preferencesManager.showCostInStatusBar) {
                        HStack(spacing: 4) {
                            Image(systemName: preferencesManager.showCostInStatusBar ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 9))
                                .foregroundColor(preferencesManager.showCostInStatusBar ? .blue : .secondary)
                            Text(localizationManager.currentLanguage == .english ?
                                 "Show cost in menu bar" :
                                 "Mostrar gasto en barra de menú")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                Spacer()
                
                // Export button
                Button(action: {
                    exportToCSV()
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help(localizationManager.currentLanguage == .english ? "Export to CSV" : "Exportar a CSV")

                // Settings button
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(pricingManager)
                        .environmentObject(localizationManager)
                        .environmentObject(liteLLMManager)
                        .environmentObject(preferencesManager)
                }

                // Language selector
                Menu {
                    ForEach(LocalizationManager.Language.allCases, id: \.self) {
                        language in
                        Button(action: {
                            localizationManager.currentLanguage = language
                        }) {
                            HStack {
                                Text(language.flag)
                                Text(language.name)
                                if localizationManager.currentLanguage == language {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(localizationManager.currentLanguage.flag)
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button(action: {
                    manager.loadData()
                }) {
                    if manager.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Today's spend and budget reset (show if using API or Looker Studio)
            if manager.dataSource == .api {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizationManager.currentLanguage == .english ? "Today's Spend" : "Gasto de Hoy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currencyManager.formatAmount(liteLLMManager.todaySpend, language: localizationManager.currentLanguage))
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(localizationManager.currentLanguage == .english ? "Budget Reset" : "Reset de Presupuesto")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let resetDate = liteLLMManager.budgetResetDate {
                            Text(formatResetDate(resetDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else if manager.dataSource == .lookerStudio {
                VStack(spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizationManager.currentLanguage == .english ? "Monthly Spend" : "Gasto Mensual")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currencyManager.formatAmount(lookerStudioManager.monthlySpend, language: localizationManager.currentLanguage))
                                .font(.headline)
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(localizationManager.currentLanguage == .english ? "Total Tokens" : "Tokens Totales")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatTokenCount(lookerStudioManager.totalTokens))
                                .font(.caption)
                                .bold()
                                .foregroundColor(.secondary)
                        }
                    }

                    // Tier & usage bar
                    if !lookerStudioManager.team.isEmpty {
                        tierUsageView
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Update banner
            if updateManager.updateAvailable {
                Button(action: {
                    updateManager.openReleaseURL()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizationManager.currentLanguage == .english ?
                                 "New version \(updateManager.latestVersion) available" :
                                 "Nueva versión \(updateManager.latestVersion) disponible")
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Text(localizationManager.currentLanguage == .english ?
                                 "Click to see release notes" :
                                 "Click para ver notas de la release")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }

            // Tabs
            Picker("", selection: $selectedTab) {
                Text(localizationManager.localized(.byMonth)).tag(0)
                Text(localizationManager.localized(.byProject)).tag(1)
                Text(localizationManager.currentLanguage == .english ? "By Model" : "Por Modelo").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // Content
            if manager.isLoading && manager.monthlyData.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(localizationManager.currentLanguage == .english ?
                         "Loading data..." : "Cargando datos...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if selectedTab == 0 {
                MonthlyView()
            } else if selectedTab == 1 {
                ProjectView()
            } else {
                ModelView()
            }
            
            Divider() 
            
            // Footer
            HStack(spacing: 0) {
                Spacer()

                HStack(spacing: 4) {
                    Text(localizationManager.localized(.lastUpdate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(manager.lastUpdate, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(" • ")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text("Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 450, height: 600)
        .overlay {
            if showLookerPromo {
                LookerPromoView(
                    isConnecting: $isConnectingFromPromo,
                    onConnect: connectFromPromo,
                    onDismiss: dismissLookerPromo
                )
            } else if showAPIBlockedNotice {
                APIBlockedNoticeView(onDismiss: dismissNotice)
            } else if hasLookerError {
                LookerExpiredView(
                    isReconnecting: $isReconnectingLooker,
                    onReconnect: reconnectLooker,
                    onDismiss: dismissLookerError
                )
            }
        }
        .onAppear {
            checkAndShowNotice()
        }
    }
}

// MARK: - Looker Studio Promo View

struct LookerPromoView: View {
    @Binding var isConnecting: Bool
    let onConnect: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject var localizationManager: LocalizationManager

    private var isEn: Bool { localizationManager.currentLanguage == .english }

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis.ascending")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(isEn ? "Get Real Cost Data" : "Obtener Datos Reales de Coste")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(isEn ? "NEW" : "NUEVO")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 10) {
                    FeatureRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        text: isEn ?
                            "Exact costs from company dashboard" :
                            "Costes exactos del dashboard de la empresa"
                    )
                    FeatureRow(
                        icon: "chart.pie.fill",
                        color: .cyan,
                        text: isEn ?
                            "Breakdown by model (Opus, Sonnet, Haiku)" :
                            "Desglose por modelo (Opus, Sonnet, Haiku)"
                    )
                    FeatureRow(
                        icon: "calendar",
                        color: .orange,
                        text: isEn ?
                            "Monthly spending history" :
                            "Historial de gasto mensual"
                    )
                    FeatureRow(
                        icon: "lock.shield.fill",
                        color: .blue,
                        text: isEn ?
                            "100% secure — your credentials stay on your device" :
                            "100% seguro — tus credenciales se quedan en tu dispositivo"
                    )
                }
                .padding(.vertical, 8)

                Text(isEn ?
                     "Connect your Google account to access Looker Studio data. Authentication happens locally in a secure window — no data is sent to third parties." :
                     "Conecta tu cuenta de Google para acceder a los datos de Looker Studio. La autenticacion se realiza localmente en una ventana segura — ningun dato se envia a terceros.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // Connect button
                Button(action: onConnect) {
                    HStack(spacing: 8) {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "link.badge.plus")
                        }
                        Text(isEn ? "Connect with Google" : "Conectar con Google")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)
                .padding(.horizontal, 20)

                // Later button
                Button(action: onDismiss) {
                    Text(isEn ? "Maybe later" : "Quiza mas tarde")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 20)
            )
            .padding(24)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - API Blocked Notice View

struct APIBlockedNoticeView: View {
    let onDismiss: () -> Void
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            // Notice card
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)

                // Title
                Text(localizationManager.currentLanguage == .english ?
                     "Important Notice" :
                     "Aviso Importante")
                    .font(.title2)
                    .fontWeight(.bold)

                // Message
                Text(localizationManager.currentLanguage == .english ?
                     "API data access has been blocked by the company. Currently, only cost estimates based on local data are available.\n\nThe displayed costs are approximations calculated from your local Claude usage files." :
                     "El acceso a datos por API ha sido bloqueado por la empresa. Actualmente, solo se pueden obtener estimaciones de costes con los datos locales.\n\nLos costes mostrados son aproximaciones calculadas a partir de tus archivos locales de uso de Claude.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Dismiss button
                Button(action: onDismiss) {
                    Text(localizationManager.currentLanguage == .english ?
                         "I Understand" :
                         "Entendido")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 10)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 20)
            )
            .padding(30)
        }
    }
}

// MARK: - Looker Session Expired View

struct LookerExpiredView: View {
    @Binding var isReconnecting: Bool
    let onReconnect: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject var localizationManager: LocalizationManager

    private var isEn: Bool { localizationManager.currentLanguage == .english }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundColor(.red)

                Text(isEn ? "Session Expired" : "Sesion Expirada")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(isEn ?
                     "Your Looker Studio session has expired.\nReconnect with Google to continue getting accurate cost data." :
                     "Tu sesion de Looker Studio ha expirado.\nReconecta con Google para seguir obteniendo datos de coste precisos.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Reconnect button
                Button(action: onReconnect) {
                    HStack(spacing: 8) {
                        if isReconnecting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isEn ? "Reconnect with Google" : "Reconectar con Google")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isReconnecting)
                .padding(.horizontal, 40)

                // Dismiss button
                Button(action: onDismiss) {
                    Text(isEn ? "Dismiss" : "Cerrar")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 20)
            )
            .padding(30)
        }
    }
}

struct MonthlyView: View {
    @EnvironmentObject var manager: ClaudeUsageManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var currencyManager: CurrencyManager
    @State private var currentPage: Int = 0

    private let itemsPerPage = 2

    private var paginatedData: [(month: String, cost: Double, details: ClaudeUsageManager.TokenBreakdown)] {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, manager.monthlyData.count)
        guard startIndex < manager.monthlyData.count else { return [] }
        return Array(manager.monthlyData[startIndex..<endIndex])
    }

    private var totalPages: Int {
        return (manager.monthlyData.count + itemsPerPage - 1) / itemsPerPage
    }

    private var pageTotal: Double {
        return paginatedData.reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(paginatedData, id: \.month) {
                        item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("📅 \(manager.formatMonth(item.month))")
                                    .font(.headline)
                                Spacer()
                                Text(currencyManager.formatAmount(item.cost, language: localizationManager.currentLanguage))
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }

                            TokenRow(
                                label: localizationManager.localized(.inputTokens),
                                count: item.details.inputTokens,
                                cost: item.details.estimatedInputCost ?? (Double(item.details.inputTokens) * 0.000003),
                                color: .blue,
                                isEstimated: item.details.estimatedInputCost != nil
                            )

                            TokenRow(
                                label: localizationManager.localized(.cacheCreation),
                                count: item.details.cacheCreationTokens,
                                cost: item.details.estimatedCacheCreationCost ?? (Double(item.details.cacheCreationTokens) * 0.00000375),
                                color: .orange,
                                isEstimated: item.details.estimatedCacheCreationCost != nil
                            )

                            TokenRow(
                                label: localizationManager.localized(.cacheRead),
                                count: item.details.cacheReadTokens,
                                cost: item.details.estimatedCacheReadCost ?? (Double(item.details.cacheReadTokens) * 0.0000003),
                                color: .purple,
                                isEstimated: item.details.estimatedCacheReadCost != nil
                            )

                            TokenRow(
                                label: localizationManager.localized(.outputTokens),
                                count: item.details.outputTokens,
                                cost: item.details.estimatedOutputCost ?? (Double(item.details.outputTokens) * 0.000015),
                                color: .red,
                                isEstimated: item.details.estimatedOutputCost != nil
                            )
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Page total
                    if totalPages > 1 {
                        HStack {
                            Text(localizationManager.currentLanguage == .english ? "Page Total" : "Total Página")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(currencyManager.formatAmount(pageTotal, language: localizationManager.currentLanguage))
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
            }

            // Pagination controls - abajo
            if totalPages > 1 {
                Divider()

                HStack(spacing: 12) {
                    // Botón Newer a la izquierda
                    Button(action: {
                        if currentPage > 0 {
                            currentPage -= 1
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text(localizationManager.currentLanguage == .english ? "Newer" : "Recientes")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(currentPage == 0 ? .gray : .blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(currentPage == 0 ? Color.gray.opacity(0.1) : Color.blue.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(currentPage == 0 ? Color.gray.opacity(0.2) : Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage == 0)

                    Spacer()

                    // Indicador de página en el centro
                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.1))
                        )

                    Spacer()

                    // Botón Older a la derecha
                    Button(action: {
                        if currentPage < totalPages - 1 {
                            currentPage += 1
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(localizationManager.currentLanguage == .english ? "Older" : "Antiguos")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(currentPage >= totalPages - 1 ? .gray : .blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(currentPage >= totalPages - 1 ? Color.gray.opacity(0.1) : Color.blue.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(currentPage >= totalPages - 1 ? Color.gray.opacity(0.2) : Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage >= totalPages - 1)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))
            }

            Divider()

            // Grand total - anclado abajo
            HStack {
                Text(localizationManager.localized(.total))
                    .font(.headline)
                Spacer()
                Text(currencyManager.formatAmount(manager.totalCost, language: localizationManager.currentLanguage))
                    .font(.title2)
                    .bold()
                    .foregroundColor(.green)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

struct ProjectView: View {
    @EnvironmentObject var manager: ClaudeUsageManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var currencyManager: CurrencyManager

    var body: some View {
        VStack(spacing: 0) {
            // Warning about local data - full width
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text(localizationManager.currentLanguage == .english ?
                     "Project data is always calculated from local files" :
                     "Los datos por proyecto siempre se calculan desde archivos locales")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(manager.projectData, id: \.project) {
                        item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("📁 \(item.project)")
                                    .font(.headline)
                                    .lineLimit(2)
                                Spacer()
                                Text(currencyManager.formatAmount(item.cost, language: localizationManager.currentLanguage))
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }

                            TokenRow(
                                label: localizationManager.localized(.input),
                                count: item.details.inputTokens,
                                cost: item.details.estimatedInputCost ?? (Double(item.details.inputTokens) * 0.000003),
                                color: .blue,
                                isEstimated: item.details.estimatedInputCost != nil
                            )

                            TokenRow(
                                label: localizationManager.localized(.cacheCreation),
                                count: item.details.cacheCreationTokens,
                                cost: item.details.estimatedCacheCreationCost ?? (Double(item.details.cacheCreationTokens) * 0.00000375),
                                color: .orange,
                                isEstimated: item.details.estimatedCacheCreationCost != nil
                            )

                            TokenRow(
                                label: localizationManager.localized(.cacheRead),
                                count: item.details.cacheReadTokens,
                                cost: item.details.estimatedCacheReadCost ?? (Double(item.details.cacheReadTokens) * 0.0000003),
                                color: .purple,
                                isEstimated: item.details.estimatedCacheReadCost != nil
                            )

                            TokenRow(
                                label: localizationManager.localized(.output),
                                count: item.details.outputTokens,
                                cost: item.details.estimatedOutputCost ?? (Double(item.details.outputTokens) * 0.000015),
                                color: .red,
                                isEstimated: item.details.estimatedOutputCost != nil
                            )
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}

struct ModelView: View {
    @EnvironmentObject var manager: ClaudeUsageManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var currencyManager: CurrencyManager

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Warning about data source
            HStack(spacing: 8) {
                Image(systemName: manager.dataSource == .local ? "info.circle.fill" : "cloud.fill")
                    .foregroundColor(manager.dataSource == .local ? .blue : .green)

                if manager.dataSource == .api {
                    Text(localizationManager.currentLanguage == .english ?
                         "Model data retrieved from LiteLLM API" :
                         "Datos de modelos obtenidos de la API LiteLLM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if manager.dataSource == .lookerStudio {
                    Text(localizationManager.currentLanguage == .english ?
                         "Data retrieved from Looker Studio dashboard" :
                         "Datos obtenidos del dashboard de Looker Studio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(localizationManager.currentLanguage == .english ?
                         "Model data calculated from local files" :
                         "Datos de modelos calculados de archivos locales")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding()
            .background(manager.dataSource == .local ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(manager.modelData, id: \.model) {
                        item in
                        HStack(spacing: 12) {
                            // Model icon and name
                            VStack(alignment: .leading, spacing: 4) {
                                Text("🤖 \(item.model)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(2)

                                // Total tokens count
                                let totalTokens = item.details.inputTokens + item.details.cacheCreationTokens + item.details.cacheReadTokens + item.details.outputTokens
                                Text("\(formatNumber(totalTokens)) tokens")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Cost
                            Text(currencyManager.formatAmount(item.cost, language: localizationManager.currentLanguage))
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}

struct TokenRow: View {
    let label: String
    let count: Int
    let cost: Double
    let color: Color
    let isEstimated: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(formatNumber(count))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text((isEstimated ? "~" : "") + String(format: "$%.2f", cost))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}