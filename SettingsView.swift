//
//  SettingsView.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var pricingManager: PricingManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var liteLLMManager: LiteLLMManager
    @EnvironmentObject var preferencesManager: PreferencesManager
    @EnvironmentObject var lookerStudioManager: LookerStudioManager
    @Environment(\.dismiss) var dismiss

    @State private var apiKey: String = ""
    @State private var isConnectingLooker: Bool = false
    @State private var standardInput: String
    @State private var standardOutput: String
    @State private var standardCacheCreation: String
    @State private var standardCacheRead: String

    @State private var longInput: String
    @State private var longOutput: String
    @State private var longCacheCreation: String
    @State private var longCacheRead: String
    
    init() {
        let pricing = PricingManager()
        _standardInput = State(initialValue: String(format: "%.2f", pricing.standardContext.inputTokens))
        _standardOutput = State(initialValue: String(format: "%.2f", pricing.standardContext.outputTokens))
        _standardCacheCreation = State(initialValue: String(format: "%.2f", pricing.standardContext.cacheCreation))
        _standardCacheRead = State(initialValue: String(format: "%.2f", pricing.standardContext.cacheRead))
        
        _longInput = State(initialValue: String(format: "%.2f", pricing.longContext.inputTokens))
        _longOutput = State(initialValue: String(format: "%.2f", pricing.longContext.outputTokens))
        _longCacheCreation = State(initialValue: String(format: "%.2f", pricing.longContext.cacheCreation))
        _longCacheRead = State(initialValue: String(format: "%.2f", pricing.longContext.cacheRead))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEnglish ? "Pricing Settings" : "Configuración de Precios")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // API Configuration Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isEnglish ? "🔑 API Configuration" : "🔑 Configuración de API")
                            .font(.subheadline)
                            .bold()

                        Text(isEnglish ? "Enter your LiteLLM API key to get exact usage data from the server. Leave empty to use local file calculation." : "Introduce tu API key de LiteLLM para obtener datos exactos del servidor. Déjalo vacío para usar el cálculo local.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(isEnglish ? "LiteLLM API Key" : "API Key de LiteLLM")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            SecureField(isEnglish ? "sk-..." : "sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        if !apiKey.isEmpty && !apiKey.hasPrefix("sk-") {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(isEnglish ? "API keys typically start with 'sk-'" : "Las API keys suelen empezar con 'sk-'")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    // Account Filter Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isEnglish ? "🏢 Account Filter" : "🏢 Filtro de Cuenta")
                            .font(.subheadline)
                            .bold()

                        Text(isEnglish ? "Filter costs by account type based on message ID prefix (msg_vrtx_* for Vertex/work, msg_01* for personal)." : "Filtra los costes por tipo de cuenta basándose en el prefijo del ID del mensaje (msg_vrtx_* para Vertex/trabajo, msg_01* para personal).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker(isEnglish ? "Account" : "Cuenta", selection: $preferencesManager.accountFilter) {
                            Text(isEnglish ? "All accounts" : "Todas las cuentas").tag(AccountFilter.all)
                            Text(isEnglish ? "Work only (Vertex)" : "Solo trabajo (Vertex)").tag(AccountFilter.workOnly)
                            Text(isEnglish ? "Personal only" : "Solo personal").tag(AccountFilter.personalOnly)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)

                    // Looker Studio Configuration Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isEnglish ? "📊 Looker Studio Connection" : "📊 Conexion Looker Studio")
                            .font(.subheadline)
                            .bold()

                        if lookerStudioManager.isConfigured {
                            // Connected state
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(isEnglish ? "Connected" : "Conectado")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            if lookerStudioManager.totalSpend > 0 {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isEnglish ? "Total Spend" : "Gasto Total")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("$\(String(format: "%.2f", lookerStudioManager.totalSpend))")
                                            .font(.caption)
                                            .bold()
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isEnglish ? "Monthly Spend" : "Gasto Mensual")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("$\(String(format: "%.2f", lookerStudioManager.monthlySpend))")
                                            .font(.caption)
                                            .bold()
                                    }
                                    Spacer()
                                }
                            }

                            HStack(spacing: 8) {
                                Button(action: openLookerLogin) {
                                    HStack(spacing: 4) {
                                        if isConnectingLooker {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                                .frame(width: 12, height: 12)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        Text(isEnglish ? "Refresh" : "Actualizar")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isConnectingLooker)

                                Button(action: clearLookerCookies) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle")
                                        Text(isEnglish ? "Disconnect" : "Desconectar")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)

                                Spacer()
                            }
                        } else {
                            // Not connected state
                            Text(isEnglish ? "Connect to Looker Studio to get real spend data from the company dashboard." : "Conecta con Looker Studio para obtener datos reales de gasto del dashboard de la empresa.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(action: openLookerLogin) {
                                HStack(spacing: 6) {
                                    if isConnectingLooker {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "link.badge.plus")
                                    }
                                    Text(isEnglish ? "Connect with Google" : "Conectar con Google")
                                }
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isConnectingLooker)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)

                    Divider()

                    // Model info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEnglish ? "Model: Claude Sonnet 4.5" : "Modelo: Claude Sonnet 4.5")
                            .font(.subheadline)
                            .bold()
                        Text(isEnglish ? "Prices per million tokens (for local calculation fallback)" : "Precios por millón de tokens (para cálculo local de respaldo)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // Standard Context
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isEnglish ? "📄 Standard Context (≤ 200K tokens)" : "📄 Contexto Estándar (≤ 200K tokens)")
                            .font(.subheadline)
                            .bold()
                        
                        PriceField(
                            label: isEnglish ? "Input tokens" : "Tokens de entrada",
                            value: $standardInput
                        )
                        PriceField(
                            label: isEnglish ? "Output tokens" : "Tokens de salida",
                            value: $standardOutput
                        )
                        PriceField(
                            label: isEnglish ? "Cache creation" : "Creación de caché",
                            value: $standardCacheCreation
                        )
                        PriceField(
                            label: isEnglish ? "Cache read" : "Lectura de caché",
                            value: $standardCacheRead
                        )
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Long Context
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isEnglish ? "📚 Long Context (> 200K tokens)" : "📚 Contexto Largo (> 200K tokens)")
                            .font(.subheadline)
                            .bold()
                        
                        PriceField(
                            label: isEnglish ? "Input tokens" : "Tokens de entrada",
                            value: $longInput
                        )
                        PriceField(
                            label: isEnglish ? "Output tokens" : "Tokens de salida",
                            value: $longOutput
                        )
                        PriceField(
                            label: isEnglish ? "Cache creation" : "Creación de caché",
                            value: $longCacheCreation
                        )
                        PriceField(
                            label: isEnglish ? "Cache read" : "Lectura de caché",
                            value: $longCacheRead
                        )
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack(spacing: 12) {
                Button(action: resetToDefaults) {
                    Text(isEnglish ? "Reset to Defaults" : "Restaurar Valores")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: saveSettings) {
                    Text(isEnglish ? "Save" : "Guardar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 600)
        .onAppear {
            loadCurrentValues()
            apiKey = liteLLMManager.apiKey
        }
    }
    
    private var isEnglish: Bool {
        localizationManager.currentLanguage == .english
    }
    
    private func loadCurrentValues() {
        standardInput = String(format: "%.2f", pricingManager.standardContext.inputTokens)
        standardOutput = String(format: "%.2f", pricingManager.standardContext.outputTokens)
        standardCacheCreation = String(format: "%.2f", pricingManager.standardContext.cacheCreation)
        standardCacheRead = String(format: "%.2f", pricingManager.standardContext.cacheRead)
        
        longInput = String(format: "%.2f", pricingManager.longContext.inputTokens)
        longOutput = String(format: "%.2f", pricingManager.longContext.outputTokens)
        longCacheCreation = String(format: "%.2f", pricingManager.longContext.cacheCreation)
        longCacheRead = String(format: "%.2f", pricingManager.longContext.cacheRead)
    }
    
    private func openLookerLogin() {
        isConnectingLooker = true
        let bridge = LookerWebBridge()
        SettingsView.activeBridge = bridge

        let lookerManager = lookerStudioManager

        bridge.show(
            onDataFetched: { data in
                DispatchQueue.main.async { [self] in
                    lookerManager.updateWithData(data)
                    lookerManager.markConnected()
                    self.isConnectingLooker = false
                    SettingsView.activeBridge = nil
                }
            },
            onDismiss: { [self] in
                DispatchQueue.main.async {
                    self.isConnectingLooker = false
                    SettingsView.activeBridge = nil
                }
            }
        )
    }

    private static var activeBridge: LookerWebBridge?

    private func clearLookerCookies() {
        lookerStudioManager.clearConnection()
    }

    private func saveSettings() {
        // Save API key
        liteLLMManager.apiKey = apiKey

        // Save pricing
        pricingManager.standardContext.inputTokens = Double(standardInput) ?? 3.00
        pricingManager.standardContext.outputTokens = Double(standardOutput) ?? 15.00
        pricingManager.standardContext.cacheCreation = Double(standardCacheCreation) ?? 3.75
        pricingManager.standardContext.cacheRead = Double(standardCacheRead) ?? 0.30

        pricingManager.longContext.inputTokens = Double(longInput) ?? 6.00
        pricingManager.longContext.outputTokens = Double(longOutput) ?? 22.50
        pricingManager.longContext.cacheCreation = Double(longCacheCreation) ?? 7.50
        pricingManager.longContext.cacheRead = Double(longCacheRead) ?? 0.60

        pricingManager.save()
        dismiss()
    }
    
    private func resetToDefaults() {
        pricingManager.reset()
        loadCurrentValues()
    }
}

struct PriceField: View {
    let label: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Text("$")
                .foregroundColor(.secondary)
            
            TextField("0.00", text: $value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            
            Text("/ 1M")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
