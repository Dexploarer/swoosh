// SwooshFlow/WorkflowReplayRun.swift — Workflow/step run, report, run store types
import Foundation
import SwooshTools

// MARK: - Workflow run
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowRun05C: Codable, Sendable, Identifiable {
    public let id: String
    public let draftID: String
    public let draftName: String
    public let mode: WorkflowReplayMode
    public var status: WorkflowRunStatus05C
    public let inputs: [String: JSONValue]
    public let startedAt: Date
    public var completedAt: Date?
    public var stepRunIDs: [String]
    public var summaryMarkdown: String?

    public init(
        id: String = UUID().uuidString, draftID: String, draftName: String,
        mode: WorkflowReplayMode = .readOnlyManual,
        status: WorkflowRunStatus05C = .pending,
        inputs: [String: JSONValue] = [:],
        startedAt: Date = Date(), completedAt: Date? = nil,
        stepRunIDs: [String] = [], summaryMarkdown: String? = nil
    ) {
        self.id = id; self.draftID = draftID; self.draftName = draftName
        self.mode = mode; self.status = status; self.inputs = inputs
        self.startedAt = startedAt; self.completedAt = completedAt
        self.stepRunIDs = stepRunIDs; self.summaryMarkdown = summaryMarkdown
    }
}

public enum WorkflowRunStatus05C: String, Codable, Sendable {
    case pending, running, completed, completedWithSkippedSteps, failed, cancelled
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Step run
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowStepRun: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let sourceStepID: String
    public let index: Int
    public let title: String
    public let toolName: String?
    public var status: WorkflowStepRunStatus
    public let startedAt: Date?
    public var completedAt: Date?
    public var outputPreview: String?
    public var errorMessage: String?
    public let skipReason: WorkflowStepSkipReason?

    public init(
        id: String = UUID().uuidString, runID: String,
        sourceStepID: String, index: Int, title: String,
        toolName: String? = nil, status: WorkflowStepRunStatus = .pending,
        startedAt: Date? = nil, completedAt: Date? = nil,
        outputPreview: String? = nil, errorMessage: String? = nil,
        skipReason: WorkflowStepSkipReason? = nil
    ) {
        self.id = id; self.runID = runID; self.sourceStepID = sourceStepID
        self.index = index; self.title = title; self.toolName = toolName
        self.status = status; self.startedAt = startedAt; self.completedAt = completedAt
        self.outputPreview = outputPreview; self.errorMessage = errorMessage
        self.skipReason = skipReason
    }
}

public enum WorkflowStepRunStatus: String, Codable, Sendable {
    case pending, running, succeeded, failed, skipped, blocked
}

public enum WorkflowStepSkipReason: String, Codable, Sendable {
    case notReadOnly, requiresApproval, humanOnly, unsupportedTool
    case missingPermission, unresolvedInput, blockedByPolicy
    case destructiveTool, writeTool, blockchainWrite, signingOrBroadcast
    case schedulingNotSupported
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Replay report
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowReplayReport: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let draftID: String
    public let draftName: String
    public let status: WorkflowRunStatus05C
    public let executedSteps: [WorkflowStepRun]
    public let skippedSteps: [WorkflowStepRun]
    public let failedSteps: [WorkflowStepRun]
    public let summaryMarkdown: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, runID: String, draftID: String, draftName: String,
        status: WorkflowRunStatus05C, executedSteps: [WorkflowStepRun],
        skippedSteps: [WorkflowStepRun], failedSteps: [WorkflowStepRun],
        summaryMarkdown: String, createdAt: Date = Date()
    ) {
        self.id = id; self.runID = runID; self.draftID = draftID; self.draftName = draftName
        self.status = status; self.executedSteps = executedSteps
        self.skippedSteps = skippedSteps; self.failedSteps = failedSteps
        self.summaryMarkdown = summaryMarkdown; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Run store
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowRunStoring: Sendable {
    func saveRun(_ run: WorkflowRun05C) async throws
    func updateRun(_ run: WorkflowRun05C) async throws
    func getRun(id: String) async throws -> WorkflowRun05C?
    func listRuns(draftID: String?) async throws -> [WorkflowRun05C]
    func saveStepRun(_ stepRun: WorkflowStepRun) async throws
    func getStepRuns(runID: String) async throws -> [WorkflowStepRun]
}

public actor InMemoryWorkflowRunStore: WorkflowRunStoring {
    private var runs: [String: WorkflowRun05C] = [:]
    private var stepRuns: [String: [WorkflowStepRun]] = [:]  // runID → steps

    public init() {}

    public func saveRun(_ run: WorkflowRun05C) { runs[run.id] = run }
    public func updateRun(_ run: WorkflowRun05C) throws {
        guard runs[run.id] != nil else { throw WorkflowStoreError.notFound(run.id) }
        runs[run.id] = run
    }
    public func getRun(id: String) -> WorkflowRun05C? { runs[id] }
    public func listRuns(draftID: String?) -> [WorkflowRun05C] {
        let all = Array(runs.values)
        if let d = draftID { return all.filter { $0.draftID == d }.sorted { $0.startedAt > $1.startedAt } }
        return all.sorted { $0.startedAt > $1.startedAt }
    }
    public func saveStepRun(_ stepRun: WorkflowStepRun) {
        stepRuns[stepRun.runID, default: []].append(stepRun)
    }
    public func getStepRuns(runID: String) -> [WorkflowStepRun] {
        (stepRuns[runID] ?? []).sorted { $0.index < $1.index }
    }
}
