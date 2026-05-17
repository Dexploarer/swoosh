// SwooshFlow/WorkflowExecutionTypes.swift — 0.5D Approval-Gated Execution Types
//
// Manual execution with per-step approval gates.
// No scheduling, no signing, no broadcasting, no git push, no file delete.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution mode and scope
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowExecutionMode: String, Codable, Sendable { case manualApprovalGated }

public enum WorkflowExecutionScope: String, Codable, Sendable {
    case allSteps, untilFirstApprovalGate, selectedReadOnlyAndApprovedSteps
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution request
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionRequest: Codable, Sendable {
    public let draftID: String
    public let providedInputs: [String: JSONValue]
    public let mode: WorkflowExecutionMode
    public let scope: WorkflowExecutionScope
    public init(
        draftID: String, providedInputs: [String: JSONValue] = [:],
        mode: WorkflowExecutionMode = .manualApprovalGated,
        scope: WorkflowExecutionScope = .allSteps
    ) { self.draftID = draftID; self.providedInputs = providedInputs; self.mode = mode; self.scope = scope }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution policy
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionPolicy: Sendable {
    public let allowReadOnly: Bool
    public let allowMediumWithApproval: Bool
    public let allowHighWithApproval: Bool
    public let allowCritical: Bool
    public let allowFileWrites: Bool
    public let allowGitCommits: Bool
    public let allowGitPush: Bool
    public let allowSwiftBuildTest: Bool
    public let allowBlockchainBuild: Bool
    public let allowSigning: Bool
    public let allowBroadcast: Bool
    public let maxSteps: Int
    public let stopOnDenial: Bool

    public static let manualApprovalGated = WorkflowExecutionPolicy(
        allowReadOnly: true, allowMediumWithApproval: true, allowHighWithApproval: true,
        allowCritical: false, allowFileWrites: true, allowGitCommits: true,
        allowGitPush: false, allowSwiftBuildTest: true, allowBlockchainBuild: true,
        allowSigning: false, allowBroadcast: false, maxSteps: 32, stopOnDenial: true
    )

    public init(
        allowReadOnly: Bool, allowMediumWithApproval: Bool, allowHighWithApproval: Bool,
        allowCritical: Bool, allowFileWrites: Bool, allowGitCommits: Bool,
        allowGitPush: Bool, allowSwiftBuildTest: Bool, allowBlockchainBuild: Bool,
        allowSigning: Bool, allowBroadcast: Bool, maxSteps: Int, stopOnDenial: Bool
    ) {
        self.allowReadOnly = allowReadOnly; self.allowMediumWithApproval = allowMediumWithApproval
        self.allowHighWithApproval = allowHighWithApproval; self.allowCritical = allowCritical
        self.allowFileWrites = allowFileWrites; self.allowGitCommits = allowGitCommits
        self.allowGitPush = allowGitPush; self.allowSwiftBuildTest = allowSwiftBuildTest
        self.allowBlockchainBuild = allowBlockchainBuild; self.allowSigning = allowSigning
        self.allowBroadcast = allowBroadcast; self.maxSteps = maxSteps; self.stopOnDenial = stopOnDenial
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution decision
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionDecision: Codable, Sendable {
    public let action: WorkflowExecutionAction
    public let reason: WorkflowStepSkipReason?
    public let requiresGate: Bool
    public let message: String

    public static func executeNow(_ msg: String) -> Self {
        .init(action: .executeNow, reason: nil, requiresGate: false, message: msg)
    }
    public static func pauseForApproval(_ msg: String) -> Self {
        .init(action: .pauseForApproval, reason: nil, requiresGate: true, message: msg)
    }
    public static func skip(_ reason: WorkflowStepSkipReason, _ msg: String) -> Self {
        .init(action: .skip, reason: reason, requiresGate: false, message: msg)
    }
    public static func block(_ reason: WorkflowStepSkipReason, _ msg: String) -> Self {
        .init(action: .block, reason: reason, requiresGate: false, message: msg)
    }
}

public enum WorkflowExecutionAction: String, Codable, Sendable {
    case executeNow, pauseForApproval, skip, block
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution decision policy
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionDecisionPolicy: Sendable {
    /// Always blocked in 0.5D regardless of policy settings.
    private static let alwaysBlocked: Set<String> = [
        "file.delete", "git.push", "git.checkout",
        "evm.wallet_connect", "evm.tx_request_signature", "evm.tx_broadcast_signed",
        "solana.wallet_connect", "solana.tx_request_signature", "solana.tx_send_signed", "solana.tx_request_airdrop",
        "vault.approve_candidate", "vault.reject_candidate",
        "workflow.enable", "workflow.delete_draft",
    ]

    /// Steps requiring per-step approval gate.
    private static let approvalGatedTools: Set<String> = [
        "swift.build", "swift.test",
        "file.patch", "file.write",
        "git.apply_patch", "git.commit",
        "evm.tx_preflight", "evm.tx_build_native_transfer", "evm.tx_build_contract_call",
        "evm.erc20_build_transfer", "evm.erc20_build_approve",
        "solana.tx_simulate", "solana.tx_build_sol_transfer", "solana.tx_build_spl_transfer",
    ]

    public init() {}

    public func decide(toolName: String, risk: ToolRisk, policy: WorkflowExecutionPolicy) -> WorkflowExecutionDecision {
        if Self.alwaysBlocked.contains(toolName) {
            return .block(.blockedByPolicy, "\(toolName) is blocked in 0.5D.")
        }

        if Self.approvalGatedTools.contains(toolName) {
            // Check policy allows the category
            if toolName.hasPrefix("swift.") && !policy.allowSwiftBuildTest {
                return .block(.blockedByPolicy, "Swift build/test not allowed by policy.")
            }
            if (toolName.hasPrefix("file.patch") || toolName.hasPrefix("file.write")) && !policy.allowFileWrites {
                return .block(.blockedByPolicy, "File writes not allowed by policy.")
            }
            if toolName.hasPrefix("git.commit") && !policy.allowGitCommits {
                return .block(.blockedByPolicy, "Git commits not allowed by policy.")
            }
            if (toolName.hasPrefix("evm.tx_build") || toolName.hasPrefix("evm.erc20_build")
                || toolName.hasPrefix("evm.tx_preflight")
                || toolName.hasPrefix("solana.tx_build") || toolName.hasPrefix("solana.tx_simulate"))
                && !policy.allowBlockchainBuild {
                return .block(.blockedByPolicy, "Blockchain transaction build not allowed by policy.")
            }
            return .pauseForApproval("\(toolName) requires per-step approval.")
        }

        // Read-only allowlist (reuse from 0.5C)
        if WorkflowStepExecutionPolicy.isAllowed(toolName) && risk == .readOnly {
            return .executeNow("Read-only tool allowed.")
        }

        if risk == .critical { return .block(.blockedByPolicy, "Critical risk blocked in 0.5D.") }
        return .skip(.blockedByPolicy, "\(toolName) not in allowlist.")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution gate
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionGate: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let stepID: String
    public let stepIndex: Int
    public let stepTitle: String
    public let toolName: String
    public let risk: ToolRisk
    public let preview: WorkflowStepApprovalPreview
    public var status: WorkflowExecutionGateStatus
    public let createdAt: Date
    public var resolvedAt: Date?
    public var resolvedBy: ToolCallOrigin?
    public var denialReason: String?

    public init(
        id: String = UUID().uuidString, runID: String, stepID: String, stepIndex: Int,
        stepTitle: String, toolName: String, risk: ToolRisk,
        preview: WorkflowStepApprovalPreview, status: WorkflowExecutionGateStatus = .pending,
        createdAt: Date = Date(), resolvedAt: Date? = nil,
        resolvedBy: ToolCallOrigin? = nil, denialReason: String? = nil
    ) {
        self.id = id; self.runID = runID; self.stepID = stepID; self.stepIndex = stepIndex
        self.stepTitle = stepTitle; self.toolName = toolName; self.risk = risk
        self.preview = preview; self.status = status; self.createdAt = createdAt
        self.resolvedAt = resolvedAt; self.resolvedBy = resolvedBy; self.denialReason = denialReason
    }
}

public enum WorkflowExecutionGateStatus: String, Codable, Sendable {
    case pending, approved, denied, expired, cancelled
}

public struct WorkflowStepApprovalPreview: Codable, Sendable {
    public let toolName: String
    public let humanSummary: String
    public let resolvedArgumentsPreview: JSONValue?
    public let expectedEffect: String
    public let riskWarnings: [String]
    public let rollbackHint: WorkflowRollbackHint?

    public init(
        toolName: String, humanSummary: String, resolvedArgumentsPreview: JSONValue? = nil,
        expectedEffect: String = "", riskWarnings: [String] = [],
        rollbackHint: WorkflowRollbackHint? = nil
    ) {
        self.toolName = toolName; self.humanSummary = humanSummary
        self.resolvedArgumentsPreview = resolvedArgumentsPreview
        self.expectedEffect = expectedEffect; self.riskWarnings = riskWarnings
        self.rollbackHint = rollbackHint
    }
}

public struct WorkflowRollbackHint: Codable, Sendable {
    public let kind: WorkflowRollbackKind
    public let description: String
    public let available: Bool
    public init(kind: WorkflowRollbackKind, description: String, available: Bool = true) {
        self.kind = kind; self.description = description; self.available = available
    }
}

public enum WorkflowRollbackKind: String, Codable, Sendable {
    case backupFile, reversePatch, gitReset, noRollback, notApplicable
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gate store
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowExecutionGateStoring: Sendable {
    func saveGate(_ gate: WorkflowExecutionGate) async throws
    func getGate(id: String) async throws -> WorkflowExecutionGate?
    func listPendingGates(runID: String?) async throws -> [WorkflowExecutionGate]
    func resolveGate(id: String, status: WorkflowExecutionGateStatus, by: ToolCallOrigin, reason: String?) async throws
}

public actor InMemoryGateStore: WorkflowExecutionGateStoring {
    private var gates: [String: WorkflowExecutionGate] = [:]
    public init() {}

    public func saveGate(_ gate: WorkflowExecutionGate) { gates[gate.id] = gate }
    public func getGate(id: String) -> WorkflowExecutionGate? { gates[id] }
    public func listPendingGates(runID: String?) -> [WorkflowExecutionGate] {
        gates.values.filter { $0.status == .pending && (runID == nil || $0.runID == runID) }
            .sorted { $0.stepIndex < $1.stepIndex }
    }
    public func resolveGate(id: String, status: WorkflowExecutionGateStatus, by origin: ToolCallOrigin, reason: String?) throws {
        guard var g = gates[id] else { throw WorkflowExecutionError.gateNotFound(id) }
        g.status = status; g.resolvedAt = Date(); g.resolvedBy = origin; g.denialReason = reason
        gates[id] = g
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution run status (extends 0.5C)
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowRunStatus05D: String, Codable, Sendable {
    case pending, running, pausedForApproval, completed, completedWithSkippedSteps, failed, cancelled
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution report
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionReport: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let draftID: String
    public let draftName: String
    public let status: WorkflowRunStatus05D
    public let executedSteps: [WorkflowStepRun]
    public let skippedSteps: [WorkflowStepRun]
    public let failedSteps: [WorkflowStepRun]
    public let gates: [WorkflowExecutionGate]
    public let pendingGateID: String?
    public let summaryMarkdown: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, runID: String, draftID: String, draftName: String,
        status: WorkflowRunStatus05D, executedSteps: [WorkflowStepRun],
        skippedSteps: [WorkflowStepRun], failedSteps: [WorkflowStepRun],
        gates: [WorkflowExecutionGate], pendingGateID: String? = nil,
        summaryMarkdown: String, createdAt: Date = Date()
    ) {
        self.id = id; self.runID = runID; self.draftID = draftID; self.draftName = draftName
        self.status = status; self.executedSteps = executedSteps; self.skippedSteps = skippedSteps
        self.failedSteps = failedSteps; self.gates = gates; self.pendingGateID = pendingGateID
        self.summaryMarkdown = summaryMarkdown; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowExecutionError: Error, Sendable {
    case draftNotFound(String)
    case runNotFound(String)
    case gateNotFound(String)
    case cannotApproveAsModel
    case cannotApproveAsWorkflow
    case highRiskRequiresConfirmation
    case runNotPaused(String)
    case gateDenied(String)
}
