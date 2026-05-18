// SwooshFlow/WorkflowDryRunReport.swift — Permission, approval, blocked, replay, report types
import Foundation
import SwooshTools

// MARK: - Permission report
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowPermissionReport: Codable, Sendable {
    public let requirements: [WorkflowPermissionCheck]
    public let allRequiredPermissionsAvailable: Bool

    public init(requirements: [WorkflowPermissionCheck], allAvailable: Bool) {
        self.requirements = requirements; self.allRequiredPermissionsAvailable = allAvailable
    }
}

public struct WorkflowPermissionCheck: Codable, Sendable, Identifiable {
    public let id: String
    public let permission: SwooshPermission
    public let currentState: PermissionState
    public let requiredForStepIDs: [String]
    public let reason: String
    public let result: WorkflowPermissionCheckResult

    public init(
        id: String = UUID().uuidString, permission: SwooshPermission,
        currentState: PermissionState, requiredForStepIDs: [String],
        reason: String, result: WorkflowPermissionCheckResult
    ) {
        self.id = id; self.permission = permission; self.currentState = currentState
        self.requiredForStepIDs = requiredForStepIDs; self.reason = reason; self.result = result
    }
}

public enum WorkflowPermissionCheckResult: String, Codable, Sendable {
    case available, requiresApproval, denied, unavailable, missing
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Approval report
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowApprovalReport: Codable, Sendable {
    public let requirements: [WorkflowApprovalRequirement]
    public let humanApprovalRequired: Bool

    public init(requirements: [WorkflowApprovalRequirement], humanApprovalRequired: Bool) {
        self.requirements = requirements; self.humanApprovalRequired = humanApprovalRequired
    }
}

public struct WorkflowApprovalRequirement: Codable, Sendable, Identifiable {
    public let id: String
    public let stepID: String
    public let toolName: String?
    public let risk: ToolRisk
    public let approvalPolicy: ApprovalPolicy
    public let reason: String

    public init(
        id: String = UUID().uuidString, stepID: String,
        toolName: String? = nil, risk: ToolRisk = .medium,
        approvalPolicy: ApprovalPolicy = .askEveryTime, reason: String
    ) {
        self.id = id; self.stepID = stepID; self.toolName = toolName
        self.risk = risk; self.approvalPolicy = approvalPolicy; self.reason = reason
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Blocked steps
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowBlockedStep: Codable, Sendable, Identifiable {
    public let id: String
    public let stepID: String
    public let title: String
    public let reason: WorkflowBlockedReason
    public let details: String

    public init(
        id: String = UUID().uuidString, stepID: String,
        title: String, reason: WorkflowBlockedReason, details: String
    ) {
        self.id = id; self.stepID = stepID; self.title = title
        self.reason = reason; self.details = details
    }
}

public enum WorkflowBlockedReason: String, Codable, Sendable {
    case humanOnlyTool, criticalTool, destructiveTool, unsupportedTool
    case missingPermission, unresolvedInput, disabledInMilestone
    case blockchainWrite, signingOrBroadcast, schedulingNotSupported
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cached replay
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowCachedReplayReport: Codable, Sendable {
    public let sourceSessionID: String
    public let mappedSteps: [WorkflowCachedReplayStep]
    public let unmappedSourceToolTraceIDs: [String]
    public let warning: String

    public init(
        sourceSessionID: String, mappedSteps: [WorkflowCachedReplayStep],
        unmappedSourceToolTraceIDs: [String] = [],
        warning: String = Self.defaultWarning
    ) {
        self.sourceSessionID = sourceSessionID; self.mappedSteps = mappedSteps
        self.unmappedSourceToolTraceIDs = unmappedSourceToolTraceIDs; self.warning = warning
    }

    public static let defaultWarning =
        "Cached replay uses prior session outputs. It does not reflect current files, chain state, balances, branches, tests, or external systems."
}

public struct WorkflowCachedReplayStep: Codable, Sendable, Identifiable {
    public let id: String
    public let stepID: String
    public let sourceToolTraceID: String
    public let cachedOutputPreview: String
    public let cachedStatus: ToolExecutionStatus

    public init(
        id: String = UUID().uuidString, stepID: String,
        sourceToolTraceID: String, cachedOutputPreview: String,
        cachedStatus: ToolExecutionStatus = .succeeded
    ) {
        self.id = id; self.stepID = stepID
        self.sourceToolTraceID = sourceToolTraceID
        self.cachedOutputPreview = cachedOutputPreview
        self.cachedStatus = cachedStatus
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Dry-run report
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowDryRunReport: Codable, Sendable, Identifiable {
    public let id: String
    public let draftID: String
    public let draftName: String
    public let mode: WorkflowDryRunMode
    public let plan: WorkflowExecutionPlan
    public let validation: WorkflowValidationResult
    public let unresolvedInputs: [WorkflowInputPrompt]
    public let permissionReport: WorkflowPermissionReport
    public let approvalReport: WorkflowApprovalReport
    public let risk: WorkflowRisk
    public let blockedSteps: [WorkflowBlockedStep]
    public let cachedReplay: WorkflowCachedReplayReport?
    public let summaryMarkdown: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, draftID: String, draftName: String,
        mode: WorkflowDryRunMode, plan: WorkflowExecutionPlan,
        validation: WorkflowValidationResult,
        unresolvedInputs: [WorkflowInputPrompt],
        permissionReport: WorkflowPermissionReport,
        approvalReport: WorkflowApprovalReport,
        risk: WorkflowRisk, blockedSteps: [WorkflowBlockedStep],
        cachedReplay: WorkflowCachedReplayReport? = nil,
        summaryMarkdown: String, createdAt: Date = Date()
    ) {
        self.id = id; self.draftID = draftID; self.draftName = draftName
        self.mode = mode; self.plan = plan; self.validation = validation
        self.unresolvedInputs = unresolvedInputs
        self.permissionReport = permissionReport
        self.approvalReport = approvalReport; self.risk = risk
        self.blockedSteps = blockedSteps; self.cachedReplay = cachedReplay
        self.summaryMarkdown = summaryMarkdown; self.createdAt = createdAt
    }
}
