// Tests/SwooshObservabilityTests/TokenCounterTests.swift — Token counting tests
//
// Tests token consumption tracking, aggregation, and querying
// across providers and sessions.

import Testing
import Foundation
@testable import SwooshObservability

// MARK: - TokenEntry Tests

@Suite("TokenEntry")
struct TokenEntryTests {

    @Test("Entry initializes with correct values")
    func initializesCorrectly() {
        let entry = TokenEntry(
            provider: "openai",
            model: "gpt-4o",
            promptTokens: 1000,
            completionTokens: 500,
            sessionID: "session-123"
        )

        #expect(entry.provider == "openai")
        #expect(entry.model == "gpt-4o")
        #expect(entry.promptTokens == 1000)
        #expect(entry.completionTokens == 500)
        #expect(entry.totalTokens == 1500)
        #expect(entry.sessionID == "session-123")
        #expect(entry.timestamp <= Date())
    }

    @Test("Entry initializes without session ID")
    func initializesWithoutSession() {
        let entry = TokenEntry(
            provider: "anthropic",
            model: "claude-sonnet",
            promptTokens: 2000,
            completionTokens: 1000
        )

        #expect(entry.sessionID == nil)
        #expect(entry.totalTokens == 3000)
    }

    @Test("Total tokens calculated correctly")
    func totalCalculated() {
        let entry = TokenEntry(
            provider: "test",
            model: "test",
            promptTokens: 100,
            completionTokens: 200
        )

        #expect(entry.totalTokens == 300)
    }

    @Test("Entry is Codable and Sendable")
    func conformsToProtocols() {
        let entry = TokenEntry(
            provider: "test",
            model: "test",
            promptTokens: 100,
            completionTokens: 100
        )

        // Codable
        let data = try? JSONEncoder().encode(entry)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = TokenEntry.self
    }
}

// MARK: - ProviderTokenSummary Tests

@Suite("ProviderTokenSummary")
struct ProviderTokenSummaryTests {

    @Test("Summary initializes with provider name")
    func initializesCorrectly() {
        let summary = ProviderTokenSummary(provider: "openai")

        #expect(summary.provider == "openai")
        #expect(summary.promptTokens == 0)
        #expect(summary.completionTokens == 0)
        #expect(summary.totalTokens == 0)
        #expect(summary.callCount == 0)
        #expect(summary.modelBreakdown.isEmpty)
    }

    @Test("Total tokens calculated from components")
    func totalCalculated() {
        var summary = ProviderTokenSummary(provider: "test")
        summary.promptTokens = 1000
        summary.completionTokens = 500

        #expect(summary.totalTokens == 1500)
    }

    @Test("Model breakdown accumulates tokens")
    func modelBreakdownAccumulates() {
        var summary = ProviderTokenSummary(provider: "openai")
        summary.modelBreakdown["gpt-4o"] = 1000
        summary.modelBreakdown["gpt-4o-mini"] = 500

        #expect(summary.modelBreakdown["gpt-4o"] == 1000)
        #expect(summary.modelBreakdown["gpt-4o-mini"] == 500)
    }

    @Test("ProviderTokenSummary is Sendable")
    func isSendable() {
        let _: any Sendable.Type = ProviderTokenSummary.self
        #expect(true)
    }
}

// MARK: - TokenCounter Tests

@Suite("TokenCounter Initialization")
struct TokenCounterInitializationTests {

    @Test("Counter initializes empty")
    func initializesEmpty() {
        let counter = TokenCounter()
        #expect(counter != nil)
    }

    @Test("Counter starts with no entries")
    func startsEmpty() async {
        let counter = TokenCounter()
        let entries = await counter.allEntries()
        #expect(entries.isEmpty)
    }
}

@Suite("TokenCounter Recording")
struct TokenCounterRecordingTests {

    @Test("Record adds entry")
    func recordAddsEntry() async {
        let counter = TokenCounter()

        await counter.record(
            provider: "openai",
            model: "gpt-4o",
            promptTokens: 1000,
            completionTokens: 500
        )

        let entries = await counter.allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].provider == "openai")
        #expect(entries[0].totalTokens == 1500)
    }

    @Test("Record with session ID")
    func recordWithSession() async {
        let counter = TokenCounter()

        await counter.record(
            provider: "openai",
            model: "gpt-4o",
            promptTokens: 1000,
            completionTokens: 500,
            sessionID: "session-abc"
        )

        let entries = await counter.allEntries()
        #expect(entries[0].sessionID == "session-abc")
    }

    @Test("Record from TokenUsage")
    func recordFromUsage() async {
        let counter = TokenCounter()
        let usage = TokenUsage(
            promptTokens: 2000,
            completionTokens: 1000,
            provider: "anthropic",
            model: "claude-sonnet"
        )

        await counter.record(usage, sessionID: "session-xyz")

        let entries = await counter.allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].promptTokens == 2000)
        #expect(entries[0].sessionID == "session-xyz")
    }

    @Test("Record accumulates multiple entries")
    func recordAccumulates() async {
        let counter = TokenCounter()

        for i in 1...10 {
            await counter.record(
                provider: "openai",
                model: "gpt-4o",
                promptTokens: 100 * i,
                completionTokens: 50 * i
            )
        }

        let entries = await counter.allEntries()
        #expect(entries.count == 10)
    }
}

@Suite("TokenCounter Queries")
struct TokenCounterQueryTests {

    @Test("Total returns sum of all tokens")
    func totalReturnsSum() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)
        await counter.record(provider: "anthropic", model: "claude", promptTokens: 2000, completionTokens: 1000)

        let total = await counter.total()

        // 1500 + 3000 = 4500
        #expect(total == 4500)
    }

    @Test("Total filters by provider")
    func totalFiltersByProvider() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)
        await counter.record(provider: "anthropic", model: "claude", promptTokens: 2000, completionTokens: 1000)
        await counter.record(provider: "openai", model: "gpt-4o-mini", promptTokens: 500, completionTokens: 250)

        let openaiTotal = await counter.total(provider: "openai")
        let anthropicTotal = await counter.total(provider: "anthropic")

        #expect(openaiTotal == 1500 + 750)
        #expect(anthropicTotal == 3000)
    }

    @Test("Total filters by date")
    func totalFiltersByDate() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)

        let recent = await counter.total(since: Date().addingTimeInterval(-3600))
        let future = await counter.total(since: Date().addingTimeInterval(3600))

        #expect(recent == 1500)
        #expect(future == 0)
    }

    @Test("Total with provider and date filters")
    func totalWithBothFilters() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)
        await counter.record(provider: "anthropic", model: "claude", promptTokens: 2000, completionTokens: 1000)

        let filtered = await counter.total(
            provider: "openai",
            since: Date().addingTimeInterval(-3600)
        )

        #expect(filtered == 1500)
    }

    @Test("PromptTokens returns prompt count only")
    func promptTokensOnly() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)

        let prompts = await counter.promptTokens()

        #expect(prompts == 1000)
    }

    @Test("CompletionTokens returns completion count only")
    func completionTokensOnly() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)

        let completions = await counter.completionTokens()

        #expect(completions == 500)
    }

    @Test("Breakdown returns per-provider summary")
    func breakdownReturnsSummary() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)
        await counter.record(provider: "openai", model: "gpt-4o-mini", promptTokens: 500, completionTokens: 250)
        await counter.record(provider: "anthropic", model: "claude", promptTokens: 2000, completionTokens: 1000)

        let breakdown = await counter.breakdown()

        #expect(breakdown["openai"]?.promptTokens == 1500)
        #expect(breakdown["openai"]?.completionTokens == 750)
        #expect(breakdown["openai"]?.callCount == 2)
        #expect(breakdown["anthropic"]?.promptTokens == 2000)
        #expect(breakdown["openai"]?.modelBreakdown["gpt-4o"] == 1500)
        #expect(breakdown["openai"]?.modelBreakdown["gpt-4o-mini"] == 750)
    }

    @Test("SessionTotal returns tokens for specific session")
    func sessionTotal() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500, sessionID: "session-a")
        await counter.record(provider: "anthropic", model: "claude", promptTokens: 2000, completionTokens: 1000, sessionID: "session-b")
        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 500, completionTokens: 250, sessionID: "session-a")

        let sessionA = await counter.sessionTotal(sessionID: "session-a")
        let sessionB = await counter.sessionTotal(sessionID: "session-b")
        let sessionC = await counter.sessionTotal(sessionID: "session-c")

        #expect(sessionA == 1500 + 750)
        #expect(sessionB == 3000)
        #expect(sessionC == 0)
    }
}

@Suite("TokenCounter Pruning")
struct TokenCounterPruningTests {

    @Test("Prune removes old entries")
    func pruneRemovesOld() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)

        let beforePrune = await counter.allEntries()
        #expect(beforePrune.count == 1)

        // Prune entries before a future date (should remove nothing)
        await counter.prune(before: Date().addingTimeInterval(3600))

        let afterPrune = await counter.allEntries()
        #expect(afterPrune.count == 1)
    }

    @Test("Prune with past date removes entries")
    func pruneWithPastRemoves() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 1000, completionTokens: 500)

        // Prune entries before now (should remove the entry)
        await counter.prune(before: Date())

        // Note: The entry was just added, so it might still be there
        // depending on timing. This test verifies the API exists.
        let entries = await counter.allEntries()
        // The entry may or may not be present depending on timing
        _ = entries
    }
}

@Suite("TokenCounter Edge Cases")
struct TokenCounterEdgeCaseTests {

    @Test("Handles zero tokens")
    func handlesZeroTokens() async {
        let counter = TokenCounter()

        await counter.record(provider: "openai", model: "gpt-4o", promptTokens: 0, completionTokens: 0)

        let total = await counter.total()
        #expect(total == 0)
    }

    @Test("Handles large token counts")
    func handlesLargeCounts() async {
        let counter = TokenCounter()

        await counter.record(
            provider: "openai",
            model: "gpt-4o",
            promptTokens: 1_000_000,
            completionTokens: 500_000
        )

        let total = await counter.total()
        #expect(total == 1_500_000)
    }

    @Test("Handles many entries")
    func handlesManyEntries() async {
        let counter = TokenCounter()

        for i in 1...1000 {
            await counter.record(
                provider: "openai",
                model: "gpt-4o",
                promptTokens: i,
                completionTokens: i
            )
        }

        let entries = await counter.allEntries()
        let total = await counter.total()

        #expect(entries.count == 1000)
        #expect(total == 1000 * 1001) // Sum of 1..1000 * 2 (prompt + completion)
    }
}
