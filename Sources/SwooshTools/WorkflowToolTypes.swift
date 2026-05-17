// SwooshTools/WorkflowToolTypes.swift — Workflow tool Input/Output types
//
// workflow.run is typed but disabled in 0.4A.
// Execution waits for 0.5A.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Workflow types
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowDraft: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let steps: [WorkflowStepPreview]
    public let requiredPermissions: [SwooshPermission]
    public let trigger: WorkflowTriggerPreview?
    public let enabled: Bool

    public init(
        id: String,
        name: String,
        summary: String,
        steps: [WorkflowStepPreview],
        requiredPermissions: [SwooshPermission],
        trigger: WorkflowTriggerPreview? = nil,
        enabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.steps = steps
        self.requiredPermissions = requiredPermissions
        self.trigger = trigger
        self.enabled = enabled
    }
}

public struct WorkflowStepPreview: Codable, Sendable {
    public let label: String
    public let toolName: String?
    public let actionKind: String

    public init(label: String, toolName: String? = nil, actionKind: String) {
        self.label = label
        self.toolName = toolName
        self.actionKind = actionKind
    }
}

public struct WorkflowTriggerPreview: Codable, Sendable {
    public let kind: String
    public let description: String

    public init(kind: String, description: String) {
        self.kind = kind
        self.description = description
    }
}

// ── workflow.draft_from_session ────────────────────────────────────

public struct WorkflowDraftFromSessionInput: Codable, Sendable {
    public let sessionID: String
    public let name: String?

    public init(sessionID: String, name: String? = nil) {
        self.sessionID = sessionID
        self.name = name
    }
}

public struct WorkflowDraftOutput: Codable, Sendable {
    public let draft: WorkflowDraft

    public init(draft: WorkflowDraft) {
        self.draft = draft
    }
}

// ── workflow.list_drafts ──────────────────────────────────────────

public struct WorkflowListDraftsInput: Codable, Sendable {
    public init() {}
}

public struct WorkflowListDraftsOutput: Codable, Sendable {
    public let drafts: [WorkflowDraft]

    public init(drafts: [WorkflowDraft]) {
        self.drafts = drafts
    }
}

// ── workflow.get_draft ────────────────────────────────────────────

public struct WorkflowGetDraftInput: Codable, Sendable {
    public let draftID: String

    public init(draftID: String) {
        self.draftID = draftID
    }
}

// ── workflow.save_draft ───────────────────────────────────────────

public struct WorkflowSaveDraftInput: Codable, Sendable {
    public let draft: WorkflowDraft

    public init(draft: WorkflowDraft) {
        self.draft = draft
    }
}

public struct WorkflowSaveDraftOutput: Codable, Sendable {
    public let draftID: String
    public let saved: Bool

    public init(draftID: String, saved: Bool) {
        self.draftID = draftID
        self.saved = saved
    }
}

// ── workflow.enable ───────────────────────────────────────────────

public struct WorkflowEnableInput: Codable, Sendable {
    public let draftID: String
    public let enabled: Bool

    public init(draftID: String, enabled: Bool) {
        self.draftID = draftID
        self.enabled = enabled
    }
}

public struct WorkflowEnableOutput: Codable, Sendable {
    public let draftID: String
    public let enabled: Bool

    public init(draftID: String, enabled: Bool) {
        self.draftID = draftID
        self.enabled = enabled
    }
}

// ── workflow.run_dry ──────────────────────────────────────────────

public struct WorkflowRunDryInput: Codable, Sendable {
    public let draftID: String

    public init(draftID: String) {
        self.draftID = draftID
    }
}

public struct WorkflowRunDryOutput: Codable, Sendable {
    public let draftID: String
    public let stepsSimulated: Int
    public let warnings: [String]
    public let wouldRequirePermissions: [SwooshPermission]

    public init(draftID: String, stepsSimulated: Int, warnings: [String], wouldRequirePermissions: [SwooshPermission]) {
        self.draftID = draftID
        self.stepsSimulated = stepsSimulated
        self.warnings = warnings
        self.wouldRequirePermissions = wouldRequirePermissions
    }
}

// ── workflow.run (typed but disabled in 0.4A) ─────────────────────

public struct WorkflowRunInput: Codable, Sendable {
    public let draftID: String
    public let confirmExecution: Bool

    public init(draftID: String, confirmExecution: Bool = false) {
        self.draftID = draftID
        self.confirmExecution = confirmExecution
    }
}

public struct WorkflowRunOutput: Codable, Sendable {
    public let runID: String
    public let status: String
    public let stepsCompleted: Int
    public let errors: [String]

    public init(runID: String, status: String, stepsCompleted: Int, errors: [String]) {
        self.runID = runID
        self.status = status
        self.stepsCompleted = stepsCompleted
        self.errors = errors
    }
}
