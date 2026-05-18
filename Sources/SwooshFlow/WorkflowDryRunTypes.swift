// SwooshFlow/WorkflowDryRunTypes.swift — 0.5B Dry Run Types
//
// All types for workflow dry-run planning: input resolution, template rendering,
// permission/approval reports, blocked steps, cached replay, and execution plan.
// No tool execution. No side effects.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Dry-run modes and scope
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowDryRunMode: String, Codable, Sendable {
    case staticAnalysis
    case cachedReplay
    case interactivePreview
}

public enum WorkflowDryRunScope: String, Codable, Sendable {
    case allSteps
    case readOnlyStepsOnly
    case untilFirstApprovalGate
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Request
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowDryRunRequest: Codable, Sendable {
    public let draftID: String
    public let mode: WorkflowDryRunMode
    public let providedInputs: [String: JSONValue]
    public let scope: WorkflowDryRunScope
    public let createdAt: Date

    public init(
        draftID: String, mode: WorkflowDryRunMode = .staticAnalysis,
        providedInputs: [String: JSONValue] = [:],
        scope: WorkflowDryRunScope = .allSteps,
        createdAt: Date = Date()
    ) {
        self.draftID = draftID; self.mode = mode
        self.providedInputs = providedInputs
        self.scope = scope; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Execution plan
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowExecutionPlan: Codable, Sendable, Identifiable {
    public let id: String
    public let draftID: String
    public var steps: [WorkflowStepPlan]
    public var variables: [ResolvedWorkflowVariable]
    public var requiredPermissions: [WorkflowPermissionRequirement]
    public var requiredApprovals: [WorkflowApprovalRequirement]
    public var estimatedRisk: WorkflowRisk
    public let isExecutableInCurrentMilestone: Bool  // always false in 0.5B

    public init(
        id: String = UUID().uuidString, draftID: String,
        steps: [WorkflowStepPlan] = [], variables: [ResolvedWorkflowVariable] = [],
        requiredPermissions: [WorkflowPermissionRequirement] = [],
        requiredApprovals: [WorkflowApprovalRequirement] = [],
        estimatedRisk: WorkflowRisk = .readOnly,
        isExecutableInCurrentMilestone: Bool = false
    ) {
        self.id = id; self.draftID = draftID; self.steps = steps
        self.variables = variables; self.requiredPermissions = requiredPermissions
        self.requiredApprovals = requiredApprovals
        self.estimatedRisk = estimatedRisk
        self.isExecutableInCurrentMilestone = isExecutableInCurrentMilestone
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Step plan
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowStepPlan: Codable, Sendable, Identifiable {
    public let id: String
    public let sourceStepID: String
    public let index: Int
    public let title: String
    public let kind: WorkflowStepKind
    public let toolName: String?
    public let resolvedArgumentsPreview: JSONValue?
    public let requiredPermissions: [SwooshPermission]
    public let risk: ToolRisk
    public let approval: ApprovalPolicy
    public var status: WorkflowStepPlanStatus
    public var cachedOutputPreview: String?
    public var warnings: [String]

    public init(
        id: String = UUID().uuidString, sourceStepID: String,
        index: Int, title: String, kind: WorkflowStepKind,
        toolName: String? = nil, resolvedArgumentsPreview: JSONValue? = nil,
        requiredPermissions: [SwooshPermission] = [],
        risk: ToolRisk = .readOnly, approval: ApprovalPolicy = .never,
        status: WorkflowStepPlanStatus = .ready,
        cachedOutputPreview: String? = nil, warnings: [String] = []
    ) {
        self.id = id; self.sourceStepID = sourceStepID
        self.index = index; self.title = title; self.kind = kind
        self.toolName = toolName; self.resolvedArgumentsPreview = resolvedArgumentsPreview
        self.requiredPermissions = requiredPermissions
        self.risk = risk; self.approval = approval
        self.status = status; self.cachedOutputPreview = cachedOutputPreview
        self.warnings = warnings
    }
}

public enum WorkflowStepPlanStatus: String, Codable, Sendable {
    case ready
    case missingInput
    case permissionMissing
    case approvalRequired
    case unsupported
    case blocked
    case disabledInThisMilestone
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Input resolution
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowInputPrompt: Codable, Sendable, Identifiable {
    public let id: String
    public let variableName: String
    public let variableType: WorkflowVariableType
    public let prompt: String
    public let defaultValue: JSONValue?
    public let required: Bool
    public let source: WorkflowInputPromptSource

    public init(
        id: String = UUID().uuidString, variableName: String,
        variableType: WorkflowVariableType, prompt: String,
        defaultValue: JSONValue? = nil, required: Bool = true,
        source: WorkflowInputPromptSource = .missingRequiredVariable
    ) {
        self.id = id; self.variableName = variableName
        self.variableType = variableType; self.prompt = prompt
        self.defaultValue = defaultValue; self.required = required
        self.source = source
    }
}

public enum WorkflowInputPromptSource: String, Codable, Sendable {
    case missingRequiredVariable
    case invalidProvidedValue
    case ambiguousVariable
    case noDefaultValue
}

public struct ResolvedWorkflowVariable: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: WorkflowVariableType
    public let value: JSONValue?
    public let source: ResolvedVariableSource
    public let isResolved: Bool

    public init(
        id: String = UUID().uuidString, name: String,
        type: WorkflowVariableType, value: JSONValue? = nil,
        source: ResolvedVariableSource = .unresolved,
        isResolved: Bool = false
    ) {
        self.id = id; self.name = name; self.type = type
        self.value = value; self.source = source; self.isResolved = isResolved
    }
}

public enum ResolvedVariableSource: String, Codable, Sendable {
    case providedInput
    case defaultValue
    case inferredFromProvenance
    case unresolved
}

public struct WorkflowInputResolutionResult: Codable, Sendable {
    public let resolvedVariables: [ResolvedWorkflowVariable]
    public let prompts: [WorkflowInputPrompt]
    public let isComplete: Bool

    public init(resolvedVariables: [ResolvedWorkflowVariable], prompts: [WorkflowInputPrompt], isComplete: Bool) {
        self.resolvedVariables = resolvedVariables; self.prompts = prompts; self.isComplete = isComplete
    }
}

// ═══════════════════════════════════════════════════════════════════
