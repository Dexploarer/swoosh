// SwooshFlow/WorkflowDraftModel.swift — 0.5A Workflow Draft Types
//
// Every generated workflow draft is: disabled, manual-only, reviewable,
// editable, auditable, permission-explicit, and non-executing.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Workflow draft (0.5A)
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowDraft05A: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var summary: String
    public var status: WorkflowDraftStatus
    public var trigger: WorkflowTrigger05A
    public var variables: [WorkflowVariable]
    public var steps: [WorkflowStep05A]
    public var requiredPermissions: [WorkflowPermissionRequirement]
    public var risk: WorkflowRisk
    public var provenance: WorkflowProvenance
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String,
        status: WorkflowDraftStatus = .draft,
        trigger: WorkflowTrigger05A = .manual,
        variables: [WorkflowVariable] = [],
        steps: [WorkflowStep05A] = [],
        requiredPermissions: [WorkflowPermissionRequirement] = [],
        risk: WorkflowRisk = .readOnly,
        provenance: WorkflowProvenance,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.name = name; self.summary = summary
        self.status = status; self.trigger = trigger
        self.variables = variables; self.steps = steps
        self.requiredPermissions = requiredPermissions
        self.risk = risk; self.provenance = provenance
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// MARK: - Status

public enum WorkflowDraftStatus: String, Codable, Sendable {
    case draft
    case saved
    case disabled
    case archived
}

// MARK: - Trigger

public enum WorkflowTrigger05A: Codable, Sendable, Equatable {
    case manual
    case placeholder(WorkflowTriggerPlaceholder)
}

public struct WorkflowTriggerPlaceholder: Codable, Sendable, Equatable {
    public let kind: WorkflowTriggerPlaceholderKind
    public let humanDescription: String

    public init(kind: WorkflowTriggerPlaceholderKind, humanDescription: String) {
        self.kind = kind; self.humanDescription = humanDescription
    }
}

public enum WorkflowTriggerPlaceholderKind: String, Codable, Sendable {
    case schedule, fileChanged, appEvent, webhook, calendarEvent
}

// MARK: - Variable

public struct WorkflowVariable: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var type: WorkflowVariableType
    public var description: String
    public var defaultValue: JSONValue?
    public var required: Bool

    public init(
        id: String = UUID().uuidString, name: String,
        type: WorkflowVariableType, description: String,
        defaultValue: JSONValue? = nil, required: Bool = true
    ) {
        self.id = id; self.name = name; self.type = type
        self.description = description; self.defaultValue = defaultValue
        self.required = required
    }
}

public enum WorkflowVariableType: String, Codable, Sendable {
    case string, integer, boolean, approvedRootID, filePath
    case gitBranch, modelRoute, permission, json
}

// MARK: - Step

public struct WorkflowStep05A: Codable, Sendable, Identifiable {
    public let id: String
    public var index: Int
    public var title: String
    public var kind: WorkflowStepKind
    public var toolName: String?
    public var argumentsTemplate: JSONValue?
    public var expectedOutput: String?
    public var requiredPermissions: [SwooshPermission]
    public var risk: ToolRisk
    public var approval: ApprovalPolicy
    public var sourceTraceID: String?

    public init(
        id: String = UUID().uuidString, index: Int, title: String,
        kind: WorkflowStepKind, toolName: String? = nil,
        argumentsTemplate: JSONValue? = nil, expectedOutput: String? = nil,
        requiredPermissions: [SwooshPermission] = [],
        risk: ToolRisk = .readOnly, approval: ApprovalPolicy = .never,
        sourceTraceID: String? = nil
    ) {
        self.id = id; self.index = index; self.title = title
        self.kind = kind; self.toolName = toolName
        self.argumentsTemplate = argumentsTemplate
        self.expectedOutput = expectedOutput
        self.requiredPermissions = requiredPermissions
        self.risk = risk; self.approval = approval
        self.sourceTraceID = sourceTraceID
    }
}

public enum WorkflowStepKind: String, Codable, Sendable {
    case toolCall, modelSummarize, humanReview, approvalGate, note, unsupported
}

// MARK: - Permission requirement

public struct WorkflowPermissionRequirement: Codable, Sendable, Identifiable {
    public let id: String
    public let permission: SwooshPermission
    public let reason: String
    public let requiredForStepIDs: [String]

    public init(id: String = UUID().uuidString, permission: SwooshPermission, reason: String, requiredForStepIDs: [String] = []) {
        self.id = id; self.permission = permission; self.reason = reason
        self.requiredForStepIDs = requiredForStepIDs
    }
}

// MARK: - Risk

public enum WorkflowRisk: String, Codable, Sendable, Comparable {
    case readOnly, low, medium, high, critical

    private var order: Int {
        switch self {
        case .readOnly: 0; case .low: 1; case .medium: 2; case .high: 3; case .critical: 4
        }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    public static func compute(from steps: [WorkflowStep05A]) -> WorkflowRisk {
        let maxRisk = steps.map { step -> WorkflowRisk in
            switch step.risk {
            case .readOnly: return .readOnly
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            case .critical: return .critical
            }
        }.max() ?? .readOnly
        return maxRisk
    }
}

// MARK: - Provenance

public struct WorkflowProvenance: Codable, Sendable {
    public let sourceSessionID: String
    public let sourceMessageIDs: [String]
    public let sourceToolTraceIDs: [String]
    public let sourceApprovedMemoryIDs: [String]
    public let generatedByModel: String?
    public let generatedAt: Date

    public init(
        sourceSessionID: String, sourceMessageIDs: [String] = [],
        sourceToolTraceIDs: [String] = [], sourceApprovedMemoryIDs: [String] = [],
        generatedByModel: String? = nil, generatedAt: Date = Date()
    ) {
        self.sourceSessionID = sourceSessionID
        self.sourceMessageIDs = sourceMessageIDs
        self.sourceToolTraceIDs = sourceToolTraceIDs
        self.sourceApprovedMemoryIDs = sourceApprovedMemoryIDs
        self.generatedByModel = generatedByModel
        self.generatedAt = generatedAt
    }
}
