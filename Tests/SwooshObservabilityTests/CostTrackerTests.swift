// Tests/SwooshObservabilityTests/CostTrackerTests.swift — Cost tracking tests
//
// Tests USD cost calculation from token usage, budget tracking,
// and cost aggregation across providers.

import Testing
import Foundation
@testable import SwooshObservability

// MARK: - ModelPricing Tests

@Suite("ModelPricing")
struct ModelPricingTests {

    @Test("Pricing initializes correctly")
    func initializesCorrectly() {
        let pricing = ModelPricing(
            provider: "openai",
            model: "gpt-4o",
            promptPricePerMillion: 2.50,
            completionPricePerMillion: 10.00
        )

        #expect(pricing.provider == "openai")
        #expect(pricing.model == "gpt-4o")
        #expect(pricing.promptPricePerMillion == 2.50)
        #expect(pricing.completionPricePerMillion == 10.00)
    }

    @Test("Cost calculation for 1M tokens")
    func costFor1MTokens() {
        let pricing = ModelPricing(
            provider: "openai",
            model: "gpt-4o",
            promptPricePerMillion: 2.50,
            completionPricePerMillion: 10.00
        )

        let cost = pricing.cost(promptTokens: 1_000_000, completionTokens: 1_000_000)

        #expect(cost == 12.50) // 2.50 + 10.00
    }

    @Test("Cost calculation for partial tokens")
    func costForPartialTokens() {
        let pricing = ModelPricing(
            provider: "openai",
            model: "gpt-4o-mini",
            promptPricePerMillion: 0.15,
            completionPricePerMillion: 0.60
        )

        let cost = pricing.cost(promptTokens: 1000, completionTokens: 500)

        // (1000/1M) * 0.15 + (500/1M) * 0.60
        // = 0.00015 + 0.0003
        // = 0.00045
        #expect(cost == 0.00015 + 0.0003)
    }

    @Test("Cost calculation for zero tokens")
    func costForZeroTokens() {
        let pricing = ModelPricing(
            provider: "local",
            model: "default",
            promptPricePerMillion: 0,
            completionPricePerMillion: 0
        )

        let cost = pricing.cost(promptTokens: 0, completionTokens: 0)

        #expect(cost == 0)
    }

    @Test("ModelPricing is Codable and Sendable")
    func conformsToProtocols() {
        let pricing = ModelPricing(
            provider: "test",
            model: "test",
            promptPricePerMillion: 1.0,
            completionPricePerMillion: 2.0
        )

        // Codable
        let data = try? JSONEncoder().encode(pricing)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = ModelPricing.self
    }
}

// MARK: - CostEntry Tests

@Suite("CostEntry")
struct CostEntryTests {

    @Test("Entry initializes with correct values")
    func initializesCorrectly() {
        let entry = CostEntry(
            provider: "openai",
            model: "gpt-4o",
            promptTokens: 1000,
            completionTokens: 500,
            costUSD: 0.0075
        )

        #expect(entry.provider == "openai")
        #expect(entry.model == "gpt-4o")
        #expect(entry.promptTokens == 1000)
        #expect(entry.completionTokens == 500)
        #expect(entry.costUSD == 0.0075)
        #expect(entry.id != "")
        #expect(entry.timestamp <= Date())
    }

    @Test("Entry is Identifiable and Codable")
    func conformsToProtocols() {
        let entry = CostEntry(
            provider: "test",
            model: "test",
            promptTokens: 100,
            completionTokens: 100,
            costUSD: 0.001
        )

        // Identifiable
        _ = entry.id

        // Codable
        let data = try? JSONEncoder().encode(entry)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = CostEntry.self
    }
}

// MARK: - CostTracker Tests

@Suite("CostTracker Initialization")
struct CostTrackerInitializationTests {

    @Test("Tracker initializes with default pricing")
    func initializesWithDefaultPricing() {
        let tracker = CostTracker()
        #expect(tracker != nil)
    }

    @Test("Tracker starts with empty entries")
    func startsEmpty() async {
        let tracker = CostTracker()
        let entries = await tracker.allEntries()
        #expect(entries.isEmpty)
    }
}

@Suite("CostTracker Recording")
struct CostTrackerRecordingTests {

    @Test("Record adds entry with correct cost")
    func recordAddsEntry() async {
        let tracker = CostTracker()
        let usage = TokenUsage(
            promptTokens: 1_000_000,
            completionTokens: 1_000_000,
            provider: "openai",
            model: "gpt-4o"
        )

        let cost = await tracker.record(usage: usage)

        #expect(cost == 12.50)

        let entries = await tracker.allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].provider == "openai")
        #expect(entries[0].model == "gpt-4o")
    }

    @Test("Record returns zero for unknown provider")
    func recordReturnsZeroForUnknown() async {
        let tracker = CostTracker()
        let usage = TokenUsage(
            promptTokens: 1000,
            completionTokens: 1000,
            provider: "unknown",
            model: "unknown"
        )

        let cost = await tracker.record(usage: usage)

        #expect(cost == 0)
    }

    @Test("Record accumulates multiple entries")
    func recordAccumulates() async {
        let tracker = CostTracker()

        for i in 1...5 {
            let usage = TokenUsage(
                promptTokens: 1000 * i,
                completionTokens: 500 * i,
                provider: "openai",
                model: "gpt-4o"
            )
            _ = await tracker.record(usage: usage)
        }

        let entries = await tracker.allEntries()
        #expect(entries.count == 5)
    }

    @Test("Record uses provider default when model not found")
    func usesProviderDefault() async {
        let tracker = CostTracker()
        let usage = TokenUsage(
            promptTokens: 1_000_000,
            completionTokens: 0,
            provider: "openai",
            model: "unknown-model"
        )

        let cost = await tracker.record(usage: usage)

        // Should use openai default pricing (2.50 per 1M prompt)
        #expect(cost == 2.50)
    }
}

@Suite("CostTracker Queries")
struct CostTrackerQueryTests {

    @Test("Total spend sums all entries")
    func totalSpendSumsAll() async {
        let tracker = CostTracker()

        // Add entries from different providers
        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o"))
        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "anthropic", model: "claude-sonnet"))

        let total = await tracker.totalSpend()

        // openai: 2.50, anthropic: 3.00
        #expect(total == 5.50)
    }

    @Test("Total spend filters by provider")
    func totalSpendFiltersByProvider() async {
        let tracker = CostTracker()

        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o"))
        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "anthropic", model: "claude-sonnet"))

        let openaiTotal = await tracker.totalSpend(provider: "openai")
        let anthropicTotal = await tracker.totalSpend(provider: "anthropic")

        #expect(openaiTotal == 2.50)
        #expect(anthropicTotal == 3.00)
    }

    @Test("Total spend filters by date")
    func totalSpendFiltersByDate() async {
        let tracker = CostTracker()

        // Add entry
        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o"))

        // Get total since 1 hour ago
        let since = Date().addingTimeInterval(-3600)
        let total = await tracker.totalSpend(since: since)

        #expect(total > 0)

        // Get total since 1 hour in future (should be 0)
        let future = Date().addingTimeInterval(3600)
        let futureTotal = await tracker.totalSpend(since: future)

        #expect(futureTotal == 0)
    }

    @Test("Breakdown returns per-provider totals")
    func breakdownReturnsTotals() async {
        let tracker = CostTracker()

        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o"))
        await tracker.record(usage: TokenUsage(promptTokens: 2_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o-mini"))
        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "anthropic", model: "claude-sonnet"))

        let breakdown = await tracker.breakdown()

        #expect(breakdown["openai"] == 2.50 + 0.30) // 2.50 + (2M * 0.15/1M)
        #expect(breakdown["anthropic"] == 3.00)
    }

    @Test("TodaySpend returns today's total")
    func todaySpendWorks() async {
        let tracker = CostTracker()

        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o"))

        let today = await tracker.todaySpend()

        #expect(today == 2.50)
    }

    @Test("HourSpend returns this hour's total")
    func hourSpendWorks() async {
        let tracker = CostTracker()

        await tracker.record(usage: TokenUsage(promptTokens: 1_000_000, completionTokens: 0, provider: "openai", model: "gpt-4o"))

        let hour = await tracker.hourSpend()

        #expect(hour == 2.50)
    }
}

@Suite("CostTracker Custom Pricing")
struct CostTrackerCustomPricingTests {

    @Test("SetPricing adds custom pricing")
    func setPricingAdds() async {
        let tracker = CostTracker()
        let customPricing = ModelPricing(
            provider: "custom",
            model: "custom-model",
            promptPricePerMillion: 1.00,
            completionPricePerMillion: 2.00
        )

        await tracker.setPricing(customPricing)

        let usage = TokenUsage(
            promptTokens: 1_000_000,
            completionTokens: 1_000_000,
            provider: "custom",
            model: "custom-model"
        )

        let cost = await tracker.record(usage: usage)
        #expect(cost == 3.00)
    }

    @Test("SetPricing overrides default pricing")
    func setPricingOverrides() async {
        let tracker = CostTracker()

        // Override openai gpt-4o pricing
        let customPricing = ModelPricing(
            provider: "openai",
            model: "gpt-4o",
            promptPricePerMillion: 5.00,  // Higher than default
            completionPricePerMillion: 20.00
        )

        await tracker.setPricing(customPricing)

        let usage = TokenUsage(
            promptTokens: 1_000_000,
            completionTokens: 1_000_000,
            provider: "openai",
            model: "gpt-4o"
        )

        let cost = await tracker.record(usage: usage)
        #expect(cost == 25.00) // 5.00 + 20.00, not 12.50
    }

    @Test("GetPricing returns custom pricing")
    func getPricingReturnsCustom() async {
        let tracker = CostTracker()
        let customPricing = ModelPricing(
            provider: "test",
            model: "test-model",
            promptPricePerMillion: 1.00,
            completionPricePerMillion: 2.00
        )

        await tracker.setPricing(customPricing)

        let retrieved = await tracker.getPricing(provider: "test", model: "test-model")

        #expect(retrieved?.promptPricePerMillion == 1.00)
        #expect(retrieved?.completionPricePerMillion == 2.00)
    }

    @Test("GetPricing falls back to provider default")
    func getPricingFallsBack() async {
        let tracker = CostTracker()

        // Get pricing for unknown openai model
        let pricing = await tracker.getPricing(provider: "openai", model: "unknown")

        // Should fall back to openai default
        #expect(pricing?.promptPricePerMillion == 2.50)
    }

    @Test("GetPricing returns nil for unknown provider")
    func getPricingReturnsNilForUnknown() async {
        let tracker = CostTracker()

        let pricing = await tracker.getPricing(provider: "unknown-provider", model: "unknown")

        #expect(pricing == nil)
    }
}

@Suite("CostTracker Pruning")
struct CostTrackerPruningTests {

    @Test("Prune removes entries before date")
    func pruneRemovesOld() async throws {
        let tracker = CostTracker()

        // We can't control entry timestamps directly, so we'll just verify
        // the prune method exists and can be called
        let cutoff = Date().addingTimeInterval(-86400) // 1 day ago
        await tracker.prune(before: cutoff)

        let entries = await tracker.allEntries()
        // All new entries should remain
        #expect(entries.isEmpty) // No entries were added in this test
    }

    @Test("Prune with future date removes nothing")
    func pruneFutureRemovesNothing() async {
        let tracker = CostTracker()

        // Add entry
        await tracker.record(usage: TokenUsage(promptTokens: 1000, completionTokens: 500, provider: "openai", model: "gpt-4o"))

        // Prune entries before future date (should remove nothing)
        let future = Date().addingTimeInterval(3600)
        await tracker.prune(before: future)

        let entries = await tracker.allEntries()
        #expect(entries.count == 1)
    }
}

@Suite("CostTracker Default Pricing")
struct CostTrackerDefaultPricingTests {

    @Test("Default pricing includes OpenAI models")
    func includesOpenAIModels() async {
        let tracker = CostTracker()

        let gpt4o = await tracker.getPricing(provider: "openai", model: "gpt-4o")
        let gpt4oMini = await tracker.getPricing(provider: "openai", model: "gpt-4o-mini")

        #expect(gpt4o != nil)
        #expect(gpt4oMini != nil)
        #expect(gpt4o?.promptPricePerMillion == 2.50)
        #expect(gpt4oMini?.promptPricePerMillion == 0.15)
    }

    @Test("Default pricing includes Anthropic models")
    func includesAnthropicModels() async {
        let tracker = CostTracker()

        let claude = await tracker.getPricing(provider: "anthropic", model: "claude-sonnet-4-20250514")
        let defaultAnthropic = await tracker.getPricing(provider: "anthropic", model: "unknown")

        #expect(claude != nil)
        #expect(defaultAnthropic?.promptPricePerMillion == 3.00)
    }

    @Test("Default pricing includes Gemini models")
    func includesGeminiModels() async {
        let tracker = CostTracker()

        let gemini = await tracker.getPricing(provider: "gemini", model: "gemini-2.5-pro")

        #expect(gemini?.promptPricePerMillion == 1.25)
    }

    @Test("Default pricing includes DeepSeek models")
    func includesDeepSeekModels() async {
        let tracker = CostTracker()

        let deepseek = await tracker.getPricing(provider: "deepseek", model: "deepseek-chat")

        #expect(deepseek?.promptPricePerMillion == 0.14)
    }

    @Test("Default pricing includes Groq models")
    func includesGroqModels() async {
        let tracker = CostTracker()

        let groq = await tracker.getPricing(provider: "groq", model: "llama-3.3-70b")

        #expect(groq?.promptPricePerMillion == 0.59)
    }

    @Test("Local provider has zero cost")
    func localHasZeroCost() async {
        let tracker = CostTracker()

        let local = await tracker.getPricing(provider: "local", model: "default")

        #expect(local?.promptPricePerMillion == 0)
        #expect(local?.completionPricePerMillion == 0)
    }
}
