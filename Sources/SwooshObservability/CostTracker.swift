// SwooshObservability/CostTracker.swift — Real-time cost calculation
//
// Calculates USD cost from token usage using per-provider pricing tables.
// Supports custom pricing overrides for self-hosted models.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Model pricing
// ═══════════════════════════════════════════════════════════════════

/// Per-model pricing (USD per 1M tokens).
public struct ModelPricing: Codable, Sendable {
    public let provider: String
    public let model: String
    public let promptPricePerMillion: Double
    public let completionPricePerMillion: Double

    public init(provider: String, model: String,
                promptPricePerMillion: Double, completionPricePerMillion: Double) {
        self.provider = provider
        self.model = model
        self.promptPricePerMillion = promptPricePerMillion
        self.completionPricePerMillion = completionPricePerMillion
    }

    /// Calculate cost for given token counts.
    public func cost(promptTokens: Int, completionTokens: Int) -> Double {
        let promptCost = Double(promptTokens) / 1_000_000 * promptPricePerMillion
        let completionCost = Double(completionTokens) / 1_000_000 * completionPricePerMillion
        return promptCost + completionCost
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cost tracker
// ═══════════════════════════════════════════════════════════════════

/// Tracks USD spend across providers with budget alerts.
public actor CostTracker {
    private var pricing: [String: ModelPricing] = makeDefaultPricing()
    private var entries: [CostEntry] = []

    public init() {}

    // ── Pricing configuration ──

    /// Set custom pricing for a model.
    public func setPricing(_ pricing: ModelPricing) {
        self.pricing["\(pricing.provider):\(pricing.model)"] = pricing
    }

    /// Get pricing for a model (falls back to provider default).
    public func getPricing(provider: String, model: String) -> ModelPricing? {
        pricing["\(provider):\(model)"] ?? pricing["\(provider):default"]
    }

    // ── Recording ──

    /// Record a cost event from token usage.
    public func record(usage: TokenUsage) -> Double {
        let modelPricing = getPricing(provider: usage.provider, model: usage.model)
        let cost = modelPricing?.cost(promptTokens: usage.promptTokens,
                                       completionTokens: usage.completionTokens) ?? 0

        let entry = CostEntry(
            provider: usage.provider,
            model: usage.model,
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            costUSD: cost
        )
        entries.append(entry)
        return cost
    }

    // ── Queries ──

    /// Total spend in a time window.
    public func totalSpend(provider: String? = nil, since: Date? = nil) -> Double {
        filtered(provider: provider, since: since)
            .reduce(0) { $0 + $1.costUSD }
    }

    /// Per-provider cost breakdown.
    public func breakdown(since: Date? = nil) -> [String: Double] {
        var result: [String: Double] = [:]
        for entry in filtered(since: since) {
            result[entry.provider, default: 0] += entry.costUSD
        }
        return result
    }

    /// Today's spend.
    public func todaySpend() -> Double {
        totalSpend(since: Calendar.current.startOfDay(for: Date()))
    }

    /// This hour's spend.
    public func hourSpend() -> Double {
        totalSpend(since: Date().addingTimeInterval(-3600))
    }

    /// All entries for persistence.
    public func allEntries() -> [CostEntry] { entries }

    /// Prune old entries.
    ///
    /// A future cutoff is treated as a no-op: pruning never removes entries
    /// that are newer than "now", so an accidental future date can't wipe
    /// live cost history.
    public func prune(before date: Date) {
        guard date <= Date() else { return }
        entries.removeAll { $0.timestamp < date }
    }

    // ── Internal ──

    private func filtered(provider: String? = nil, since: Date? = nil) -> [CostEntry] {
        entries.filter { entry in
            if let p = provider, entry.provider != p { return false }
            if let s = since, entry.timestamp < s { return false }
            return true
        }
    }
}

private func makeDefaultPricing() -> [String: ModelPricing] {
    let defaults: [(String, String, Double, Double)] = [
        ("openai", "gpt-4o", 2.50, 10.00), ("openai", "gpt-4o-mini", 0.15, 0.60),
        ("openai", "gpt-4.1", 2.00, 8.00), ("openai", "gpt-4.1-mini", 0.40, 1.60),
        ("openai", "gpt-4.1-nano", 0.10, 0.40), ("openai", "o3", 10.00, 40.00),
        ("openai", "o4-mini", 1.10, 4.40), ("openai", "codex-mini", 1.50, 6.00),
        ("openai", "default", 2.50, 10.00),
        ("anthropic", "claude-sonnet-4-20250514", 3.00, 15.00),
        ("anthropic", "claude-3.5-sonnet", 3.00, 15.00),
        ("anthropic", "claude-3.5-haiku", 0.80, 4.00),
        ("anthropic", "claude-3-opus", 15.00, 75.00), ("anthropic", "default", 3.00, 15.00),
        ("gemini", "gemini-2.5-pro", 1.25, 10.00), ("gemini", "gemini-2.5-flash", 0.15, 0.60),
        ("gemini", "default", 1.25, 10.00),
        ("deepseek", "deepseek-chat", 0.14, 0.28), ("deepseek", "deepseek-reasoner", 0.55, 2.19),
        ("deepseek", "default", 0.14, 0.28),
        ("groq", "llama-3.3-70b", 0.59, 0.79), ("groq", "llama-4-scout-17b", 0.11, 0.34),
        ("groq", "default", 0.59, 0.79),
        ("local", "default", 0, 0),
    ]
    var result: [String: ModelPricing] = [:]
    for (provider, model, prompt, completion) in defaults {
        result["\(provider):\(model)"] = ModelPricing(
            provider: provider, model: model,
            promptPricePerMillion: prompt, completionPricePerMillion: completion)
    }
    return result
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cost entry
// ═══════════════════════════════════════════════════════════════════

public struct CostEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let provider: String
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let costUSD: Double
    public let timestamp: Date

    public init(provider: String, model: String,
                promptTokens: Int, completionTokens: Int,
                costUSD: Double) {
        self.id = UUID().uuidString
        self.provider = provider
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.costUSD = costUSD
        self.timestamp = Date()
    }
}
