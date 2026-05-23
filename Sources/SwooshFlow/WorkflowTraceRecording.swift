// SwooshFlow/WorkflowTraceRecording.swift — 0.5E Runtime trace recorder
//
// Records per-step traces for live `workflow.run` invocations so
// engineering rule #4 ("every workflow is replayable") actually applies
// to runtime calls and not just to engine-mediated runs.
//
// The wire-in lives in `TracingWorkflowStepExecutor`. The daemon and CLI
// inject `InMemoryWorkflowTraceRecorder()` at startup; durable
// (ActantDB-backed) recorders are a future swap that doesn't touch
// callers.

import Foundation
import SwooshTools

// MARK: - Per-step trace shape

/// One step from a runtime `workflow.run` invocation.
///
/// `error` is set when the step threw; both `output` and `error` may be
/// present if a redactor decided the output was sensitive but the step
/// itself succeeded. Timestamps come from the executor — not from
/// `Date()` inside the tool — to keep replay deterministic.
public struct WorkflowStepTrace: Codable, Sendable, Equatable {
    public let workflowID: String
    public let toolName: String
    public let argumentsJSON: String
    public let outputJSON: String?
    public let error: String?
    public let durationMs: Int
    public let startedAt: Date

    public init(
        workflowID: String,
        toolName: String,
        argumentsJSON: String,
        outputJSON: String?,
        error: String?,
        durationMs: Int,
        startedAt: Date
    ) {
        self.workflowID = workflowID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.outputJSON = outputJSON
        self.error = error
        self.durationMs = durationMs
        self.startedAt = startedAt
    }
}

// MARK: - Recorder protocol

/// Records workflow-step traces from live runs. A no-op default is
/// available via `NoopWorkflowTraceRecorder()` so production callers
/// that don't care about traces can opt out without nil-checking.
public protocol WorkflowTraceRecording: Sendable {
    func record(_ trace: WorkflowStepTrace) async
    func tail(workflowID: String, limit: Int) async -> [WorkflowStepTrace]
    func clear(workflowID: String) async
}

// MARK: - In-memory recorder

/// Default recorder — keeps per-workflow traces in a bounded ring
/// buffer. Survives the daemon process but not a restart; a durable
/// `ActantDB`-backed recorder can replace it via dependency injection.
public actor InMemoryWorkflowTraceRecorder: WorkflowTraceRecording {
    private var traces: [String: [WorkflowStepTrace]] = [:]
    private let perWorkflowCap: Int

    public init(perWorkflowCap: Int = 1024) {
        self.perWorkflowCap = perWorkflowCap
    }

    public func record(_ trace: WorkflowStepTrace) async {
        var bucket = traces[trace.workflowID] ?? []
        bucket.append(trace)
        // Drop oldest if we'd exceed the cap.
        if bucket.count > perWorkflowCap {
            bucket.removeFirst(bucket.count - perWorkflowCap)
        }
        traces[trace.workflowID] = bucket
    }

    public func tail(workflowID: String, limit: Int) async -> [WorkflowStepTrace] {
        let bucket = traces[workflowID] ?? []
        if bucket.count <= limit { return bucket }
        return Array(bucket.suffix(limit))
    }

    public func clear(workflowID: String) async {
        traces.removeValue(forKey: workflowID)
    }
}

// MARK: - No-op recorder

/// Convenient default for callers that don't want trace recording.
/// Cheaper than `Optional<WorkflowTraceRecording>` nil-checks at the
/// hot path.
public struct NoopWorkflowTraceRecorder: WorkflowTraceRecording {
    public init() {}
    public func record(_ trace: WorkflowStepTrace) async {}
    public func tail(workflowID: String, limit: Int) async -> [WorkflowStepTrace] { [] }
    public func clear(workflowID: String) async {}
}
