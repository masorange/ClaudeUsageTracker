//
//  PricingManager.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import Foundation
import Combine

class PricingManager: ObservableObject {
    @Published var standardContext: ContextPricing
    @Published var longContext: ContextPricing

    private let defaults = UserDefaults.standard

    // Vertex AI regional endpoint multiplier (10% premium over global)
    static let vertexRegionalMultiplier: Double = 1.1

    // Model pricing in USD per 1M tokens (Vertex AI Regional pricing)
    struct ModelPricing {
        let inputPrice: Double   // USD per 1M tokens
        let outputPrice: Double  // USD per 1M tokens

        // Cache pricing (Anthropic standard multipliers applied on top of regional pricing)
        var cacheCreation: Double { inputPrice * 1.25 }  // 1.25x input price (5min TTL)
        var cacheRead: Double { inputPrice * 0.10 }      // 10% of input price
    }

    // Pricing dictionary for all supported models (prices in USD per 1M tokens)
    // Anthropic base pricing (global endpoints)
    static let modelPricing: [String: ModelPricing] = [
        // Claude Opus 4.6 models
        "claude-opus-4-6": ModelPricing(inputPrice: 5.00, outputPrice: 25.00),
        "claude-4-6-opus": ModelPricing(inputPrice: 5.00, outputPrice: 25.00),

        // Claude Opus 4.5 models
        "claude-opus-4-5": ModelPricing(inputPrice: 5.00, outputPrice: 25.00),
        "claude-4-5-opus": ModelPricing(inputPrice: 5.00, outputPrice: 25.00),
        "claude-opus-4-5-20251101": ModelPricing(inputPrice: 5.00, outputPrice: 25.00),

        // Claude Sonnet 4.6 models
        "claude-sonnet-4-6": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-4-6-sonnet": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),

        // Claude Sonnet 4.5 models
        "claude-sonnet-4-5": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-4-5-sonnet": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-sonnet-4-5-20251022": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),
        "claude-sonnet-4-5-20250929": ModelPricing(inputPrice: 3.00, outputPrice: 15.00),

        // Claude Haiku models
        "claude-haiku-4-5-20251001": ModelPricing(inputPrice: 1.00, outputPrice: 5.00),
        "claude-4-5-haiku": ModelPricing(inputPrice: 1.00, outputPrice: 5.00),
        "haiku": ModelPricing(inputPrice: 1.00, outputPrice: 5.00),

        // Gemini models (no regional multiplier - Google native)
        "gemini-3-pro-preview": ModelPricing(inputPrice: 2.00, outputPrice: 12.00),
        "gemini-2.5-pro": ModelPricing(inputPrice: 1.25, outputPrice: 10.00),
        "gemini-2.5-flash": ModelPricing(inputPrice: 0.30, outputPrice: 2.50),
        "gemini-2.5-flash-lite": ModelPricing(inputPrice: 0.10, outputPrice: 0.40),
        "gemini-3-flash-preview": ModelPricing(inputPrice: 0.30, outputPrice: 2.50),
        "gemini-embedding-001": ModelPricing(inputPrice: 0.15, outputPrice: 0.00),
        "bge-m3": ModelPricing(inputPrice: 0.15, outputPrice: 0.00),
    ]

    // Default pricing (Sonnet base) for unknown models
    static let defaultModelPricing = ModelPricing(inputPrice: 3.00, outputPrice: 15.00)

    // Get pricing for a specific model
    static func getPricing(for modelName: String) -> ModelPricing {
        // Try exact match first
        if let pricing = modelPricing[modelName] {
            return pricing
        }

        // Try partial match (model name might have prefixes/suffixes)
        let lowercased = modelName.lowercased()
        for (key, pricing) in modelPricing {
            if lowercased.contains(key.lowercased()) || key.lowercased().contains(lowercased) {
                return pricing
            }
        }

        // Fallback to default (Sonnet pricing)
        return defaultModelPricing
    }

    struct ContextPricing: Codable {
        var inputTokens: Double
        var outputTokens: Double
        var cacheCreation: Double
        var cacheRead: Double

        // Anthropic base pricing (without regional multiplier)
        static let standardDefault = ContextPricing(
            inputTokens: 3.00,
            outputTokens: 15.00,
            cacheCreation: 3.75,
            cacheRead: 0.30
        )

        static let longDefault = ContextPricing(
            inputTokens: 6.00,
            outputTokens: 22.50,
            cacheCreation: 7.50,
            cacheRead: 0.60
        )
    }
    
    init() {
        // Load saved pricing or use defaults
        if let standardData = defaults.data(forKey: "standardContextPricing"),
           let standard = try? JSONDecoder().decode(ContextPricing.self, from: standardData) {
            self.standardContext = standard
        } else {
            self.standardContext = .standardDefault
        }
        
        if let longData = defaults.data(forKey: "longContextPricing"),
           let long = try? JSONDecoder().decode(ContextPricing.self, from: longData) {
            self.longContext = long
        } else {
            self.longContext = .longDefault
        }
    }
    
    func save() {
        if let standardData = try? JSONEncoder().encode(standardContext) {
            defaults.set(standardData, forKey: "standardContextPricing")
        }
        if let longData = try? JSONEncoder().encode(longContext) {
            defaults.set(longData, forKey: "longContextPricing")
        }
    }
    
    func reset() {
        standardContext = .standardDefault
        longContext = .longDefault
        save()
    }
    
    func getPricing(contextSize: Int) -> ContextPricing {
        return contextSize > 200_000 ? longContext : standardContext
    }
    
    // Helper to convert to price per token (from price per million)
    func pricePerToken(_ pricePerMillion: Double) -> Double {
        return pricePerMillion / 1_000_000
    }
}
