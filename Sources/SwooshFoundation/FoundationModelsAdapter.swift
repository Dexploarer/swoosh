// SwooshFoundation/FoundationModelsAdapter.swift — 0.9Q Apple Foundation Models adapter
//
// Tier 1: Apple's on-device ~3B model.
// Use for: intent classification, tool argument drafting, entity extraction,
//          memory candidate extraction, risk scoring, short summarization.
// Do NOT use as the main brain. Use as the private local control plane.
//
// **Status**: helpers are kernel-optional. None of these methods are
// wired by default from the agent kernel — they exist so that callers
// (Scout review queue, agent-loop pre-approval scoring, calendar
// scrape) can pull on them without re-implementing on-device guided
// generation. New consumers should construct a single shared
// `FoundationModelAdapter` and reuse it; the actor caches the
// `LanguageModelSession` and `resetSession()` is the only way to free
// its context budget.

#if canImport(FoundationModels)
import FoundationModels
import Foundation

// MARK: - Guided generation types

/// Extract structured data from natural language using Apple's on-device model.
/// These types use @Generable for compile-time constrained generation.

@Generable
public struct ExtractedIntent {
    @Guide(description: "The user's primary intent in 1-3 words.")
    public var intent: String

    @Guide(description: "Confidence from 0.0 to 1.0.")
    public var confidence: Double

    @Guide(description: "Required tool names, if any.")
    public var suggestedTools: [String]
}

@Generable
public struct ExtractedMemoryCandidate {
    @Guide(description: "The factual content to remember.")
    public var content: String

    @Guide(.anyOf(["fact", "preference", "project", "person", "place", "workflow", "toolQuirk", "reusableDecision"]))
    public var category: String

    @Guide(description: "Confidence: low, medium, high, certain.")
    public var confidence: String
}

@Generable
public struct RiskAssessment {
    @Guide(description: "Risk level: none, low, medium, high, critical.")
    public var risk: String

    @Guide(description: "One-sentence explanation of the risk.")
    public var reason: String
}

@Generable
public struct ExtractedCalendarItem {
    public var title: String
    public var date: String
    public var time: String?
    public var duration: String?
    public var isAllDay: Bool
}

// MARK: - Foundation Models session wrapper

/// Thin wrapper around LanguageModelSession for Swoosh's local control plane.
public actor FoundationModelAdapter {
    private var session: LanguageModelSession?

    public init() {}

    private func ensureSession() -> LanguageModelSession {
        if let s = session { return s }
        let s = LanguageModelSession()
        session = s
        return s
    }

    /// Classify intent locally and for free.
    public func classifyIntent(userMessage: String) async throws -> ExtractedIntent {
        let s = ensureSession()
        let response = try await s.respond(
            to: "Classify the user's intent: \(userMessage)",
            generating: ExtractedIntent.self
        )
        return response.content
    }

    /// Extract memory candidates from a transcript snippet.
    public func extractMemoryCandidates(from text: String) async throws -> [ExtractedMemoryCandidate] {
        let s = ensureSession()
        let response = try await s.respond(
            to: "Extract facts, preferences, or decisions worth remembering from this text:\n\(text)",
            generating: [ExtractedMemoryCandidate].self
        )
        return response.content
    }

    /// Score the risk of a tool call.
    public func assessRisk(toolName: String, arguments: String) async throws -> RiskAssessment {
        let s = ensureSession()
        let response = try await s.respond(
            to: "Assess the risk of calling tool '\(toolName)' with arguments: \(arguments)",
            generating: RiskAssessment.self
        )
        return response.content
    }

    /// Extract calendar items from natural language.
    public func extractCalendarItems(from text: String) async throws -> [ExtractedCalendarItem] {
        let s = ensureSession()
        let response = try await s.respond(
            to: "Extract any dates, deadlines, or calendar events from:\n\(text)",
            generating: [ExtractedCalendarItem].self
        )
        return response.content
    }

    /// Short summarization.
    public func summarize(_ text: String, style: String = "concise") async throws -> String {
        let s = ensureSession()
        let response = try await s.respond(to: "Summarize the following in a \(style) style:\n\(text)")
        return response.content
    }

    /// Reset session to free context window.
    public func resetSession() {
        session = nil
    }
}
#else
// Stub for platforms where FoundationModels is not available
public actor FoundationModelAdapter {
    public init() {}
}
#endif
