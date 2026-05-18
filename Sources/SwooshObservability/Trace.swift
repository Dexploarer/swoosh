// SwooshObservability/Trace.swift — Trace aggregation model
//
// A Trace groups related Spans into a single logical operation,
// e.g. one user message → agent turn → tool calls → response.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trace
// ═══════════════════════════════════════════════════════════════════

/// A complete trace of one logical operation (agent turn, workflow step, etc.).
public struct Trace: Codable, Sendable, Identifiable {
    public let id: String
    public var spans: [Span]
    public var status: SpanStatus
    public let startTime: Date
    public var endTime: Date?
    public var metadata: [String: String]

    /// Total duration.
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    /// Root span (the first span without a parent).
    public var rootSpan: Span? {
        spans.first { $0.parentSpanID == nil }
    }

    /// Total tokens consumed across all inference spans.
    public var totalTokens: Int {
        spans.compactMap(\.tokenUsage).reduce(0) { $0 + $1.totalTokens }
    }

    /// Total cost across all spans.
    public var totalCostUSD: Double {
        spans.compactMap(\.costUSD).reduce(0, +)
    }

    /// Number of tool calls in this trace.
    public var toolCallCount: Int {
        spans.filter { $0.kind == .tool }.count
    }

    /// Number of inference calls.
    public var inferenceCount: Int {
        spans.filter { $0.kind == .inference }.count
    }

    public init(id: String = UUID().uuidString, metadata: [String: String] = [:]) {
        self.id = id
        self.spans = []
        self.status = .running
        self.startTime = Date()
        self.endTime = nil
        self.metadata = metadata
    }

    public mutating func addSpan(_ span: Span) {
        spans.append(span)
    }

    public mutating func finish(status: SpanStatus = .ok) {
        self.status = status
        self.endTime = Date()
    }
}
