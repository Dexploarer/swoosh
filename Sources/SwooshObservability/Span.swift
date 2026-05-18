// SwooshObservability/Span.swift — OpenTelemetry-inspired span model
//
// Structured tracing for every agent action: inference calls, tool
// executions, approval gates, and system events. Spans nest into
// traces for full-path observability.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Span kinds
// ═══════════════════════════════════════════════════════════════════

/// Classification of what a span represents.
public enum SpanKind: String, Codable, Sendable {
    case agent          // Top-level agent turn
    case inference      // LLM call (prompt → completion)
    case tool           // Tool execution
    case approval       // Approval gate wait
    case workflow       // Workflow step
    case system         // Internal system operation
    case browser        // Browser automation action
    case media          // Media pipeline operation
    case skill          // Skill matching/execution
}

/// Terminal status of a span.
public enum SpanStatus: String, Codable, Sendable {
    case running
    case ok
    case error
    case cancelled
    case timedOut
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Span event
// ═══════════════════════════════════════════════════════════════════

/// A timestamped event within a span (e.g. "tool returned", "budget warning").
public struct SpanEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let timestamp: Date
    public var attributes: [String: String]

    public init(name: String, attributes: [String: String] = [:]) {
        self.id = UUID().uuidString
        self.name = name
        self.timestamp = Date()
        self.attributes = attributes
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Token usage
// ═══════════════════════════════════════════════════════════════════

/// Token counts for an inference call.
public struct TokenUsage: Codable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public var provider: String
    public var model: String

    public init(promptTokens: Int, completionTokens: Int,
                provider: String, model: String) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.provider = provider
        self.model = model
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Span
// ═══════════════════════════════════════════════════════════════════

/// A single unit of work within a trace. Spans form a tree via parentSpanID.
public struct Span: Codable, Sendable, Identifiable {
    public let id: String
    public let traceID: String
    public var parentSpanID: String?
    public let name: String
    public let kind: SpanKind
    public var status: SpanStatus
    public var attributes: [String: String]
    public var events: [SpanEvent]
    public let startTime: Date
    public var endTime: Date?
    public var tokenUsage: TokenUsage?
    public var costUSD: Double?

    /// Duration in seconds, or nil if still running.
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    public init(
        traceID: String,
        parentSpanID: String? = nil,
        name: String,
        kind: SpanKind,
        attributes: [String: String] = [:]
    ) {
        self.id = UUID().uuidString
        self.traceID = traceID
        self.parentSpanID = parentSpanID
        self.name = name
        self.kind = kind
        self.status = .running
        self.attributes = attributes
        self.events = []
        self.startTime = Date()
        self.endTime = nil
        self.tokenUsage = nil
        self.costUSD = nil
    }

    /// End this span with a status.
    public mutating func finish(status: SpanStatus = .ok) {
        self.status = status
        self.endTime = Date()
    }

    /// Add an event to this span.
    public mutating func addEvent(_ name: String, attributes: [String: String] = [:]) {
        events.append(SpanEvent(name: name, attributes: attributes))
    }
}
