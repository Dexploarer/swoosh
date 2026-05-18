// SwooshObservability/TokenCounter.swift — Per-provider token tracking
//
// Tracks prompt and completion tokens per provider per session,
// with rolling windows and historical totals.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Token counter
// ═══════════════════════════════════════════════════════════════════

/// Tracks token consumption per provider with time-windowed aggregation.
public actor TokenCounter {
    private var entries: [TokenEntry] = []

    public init() {}

    // ── Recording ──

    /// Record a token usage event.
    public func record(
        provider: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        sessionID: String? = nil
    ) {
        let entry = TokenEntry(
            provider: provider,
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            sessionID: sessionID
        )
        entries.append(entry)
    }

    /// Record from a TokenUsage struct.
    public func record(_ usage: TokenUsage, sessionID: String? = nil) {
        record(
            provider: usage.provider,
            model: usage.model,
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            sessionID: sessionID
        )
    }

    // ── Queries ──

    /// Total tokens for a provider in a time window.
    public func total(provider: String? = nil, since: Date? = nil) -> Int {
        filtered(provider: provider, since: since)
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// Prompt tokens only.
    public func promptTokens(provider: String? = nil, since: Date? = nil) -> Int {
        filtered(provider: provider, since: since)
            .reduce(0) { $0 + $1.promptTokens }
    }

    /// Completion tokens only.
    public func completionTokens(provider: String? = nil, since: Date? = nil) -> Int {
        filtered(provider: provider, since: since)
            .reduce(0) { $0 + $1.completionTokens }
    }

    /// Per-provider breakdown.
    public func breakdown(since: Date? = nil) -> [String: ProviderTokenSummary] {
        var result: [String: ProviderTokenSummary] = [:]
        for entry in filtered(since: since) {
            var summary = result[entry.provider, default: ProviderTokenSummary(provider: entry.provider)]
            summary.promptTokens += entry.promptTokens
            summary.completionTokens += entry.completionTokens
            summary.callCount += 1
            if let existing = summary.modelBreakdown[entry.model] {
                summary.modelBreakdown[entry.model] = existing + entry.totalTokens
            } else {
                summary.modelBreakdown[entry.model] = entry.totalTokens
            }
            result[entry.provider] = summary
        }
        return result
    }

    /// Session-specific total.
    public func sessionTotal(sessionID: String) -> Int {
        entries.filter { $0.sessionID == sessionID }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// All entries (for persistence).
    public func allEntries() -> [TokenEntry] { entries }

    /// Clear entries older than a date.
    public func prune(before date: Date) {
        entries.removeAll { $0.timestamp < date }
    }

    // ── Internal ──

    private func filtered(provider: String? = nil, since: Date? = nil) -> [TokenEntry] {
        entries.filter { entry in
            if let p = provider, entry.provider != p { return false }
            if let s = since, entry.timestamp < s { return false }
            return true
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Supporting types
// ═══════════════════════════════════════════════════════════════════

public struct TokenEntry: Codable, Sendable {
    public let provider: String
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public let sessionID: String?
    public let timestamp: Date

    public init(provider: String, model: String,
                promptTokens: Int, completionTokens: Int,
                sessionID: String? = nil) {
        self.provider = provider
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.sessionID = sessionID
        self.timestamp = Date()
    }
}

public struct ProviderTokenSummary: Sendable {
    public let provider: String
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0
    public var totalTokens: Int { promptTokens + completionTokens }
    public var callCount: Int = 0
    public var modelBreakdown: [String: Int] = [:]

    public init(provider: String) {
        self.provider = provider
    }
}
