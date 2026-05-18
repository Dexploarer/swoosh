// SwooshTools/VaultPermScoutToolTypes.swift — Vault, Permission, Scout, Audit tool types
//
// Extracted from CoreToolTypes.swift for file size compliance.

import Foundation

// MARK: - Vault tools (memory candidates)
// ═══════════════════════════════════════════════════════════════════

// ── vault.list_candidates ─────────────────────────────────────────

public struct ListCandidatesInput: Codable, Sendable {
    public let status: CandidateStatus?
    public let limit: Int?

    public init(status: CandidateStatus? = nil, limit: Int? = nil) {
        self.status = status
        self.limit = limit
    }
}

public struct ListCandidatesOutput: Codable, Sendable {
    public let candidates: [MemoryCandidate]

    public init(candidates: [MemoryCandidate]) {
        self.candidates = candidates
    }
}

// ── vault.get_candidate ───────────────────────────────────────────

public struct GetCandidateInput: Codable, Sendable {
    public let candidateID: String

    public init(candidateID: String) {
        self.candidateID = candidateID
    }
}

public struct GetCandidateOutput: Codable, Sendable {
    public let candidate: MemoryCandidate?

    public init(candidate: MemoryCandidate?) {
        self.candidate = candidate
    }
}

// ── vault.propose_candidate ───────────────────────────────────────

public struct ProposeMemoryCandidateInput: Codable, Sendable {
    public let text: String
    public let category: MemoryCategory
    public let sensitivity: Sensitivity
    public let confidence: Double
    public let evidence: [EvidencePointer]

    public init(
        text: String,
        category: MemoryCategory,
        sensitivity: Sensitivity,
        confidence: Double,
        evidence: [EvidencePointer]
    ) {
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct ProposeMemoryCandidateOutput: Codable, Sendable {
    public let candidateID: String
    public let status: CandidateStatus

    public init(candidateID: String, status: CandidateStatus) {
        self.candidateID = candidateID
        self.status = status
    }
}

// ── vault.approve_candidate ───────────────────────────────────────

public struct ApproveMemoryCandidateInput: Codable, Sendable {
    public let candidateID: String
    public let finalText: String?

    public init(candidateID: String, finalText: String? = nil) {
        self.candidateID = candidateID
        self.finalText = finalText
    }
}

public struct ApproveMemoryCandidateOutput: Codable, Sendable {
    public let approvedMemoryID: String

    public init(approvedMemoryID: String) {
        self.approvedMemoryID = approvedMemoryID
    }
}

// ── vault.reject_candidate ────────────────────────────────────────

public struct RejectMemoryCandidateInput: Codable, Sendable {
    public let candidateID: String
    public let reason: String?

    public init(candidateID: String, reason: String? = nil) {
        self.candidateID = candidateID
        self.reason = reason
    }
}

public struct RejectMemoryCandidateOutput: Codable, Sendable {
    public let candidateID: String
    public let status: CandidateStatus

    public init(candidateID: String, status: CandidateStatus) {
        self.candidateID = candidateID
        self.status = status
    }
}

// ── vault.edit_candidate ──────────────────────────────────────────

public struct EditMemoryCandidateInput: Codable, Sendable {
    public let candidateID: String
    public let newText: String
    public let newCategory: MemoryCategory?
    public let newSensitivity: Sensitivity?

    public init(
        candidateID: String,
        newText: String,
        newCategory: MemoryCategory? = nil,
        newSensitivity: Sensitivity? = nil
    ) {
        self.candidateID = candidateID
        self.newText = newText
        self.newCategory = newCategory
        self.newSensitivity = newSensitivity
    }
}

public struct EditMemoryCandidateOutput: Codable, Sendable {
    public let candidateID: String
    public let status: CandidateStatus

    public init(candidateID: String, status: CandidateStatus) {
        self.candidateID = candidateID
        self.status = status
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Permissions tools
// ═══════════════════════════════════════════════════════════════════

// ── permissions.summary ───────────────────────────────────────────

public struct PermissionSummaryInput: Codable, Sendable {
    public init() {}
}

public struct PermissionSummaryOutput: Codable, Sendable {
    public let permissions: [PermissionEntry]
    public let markdown: String

    public init(permissions: [PermissionEntry], markdown: String) {
        self.permissions = permissions
        self.markdown = markdown
    }
}

public struct PermissionEntry: Codable, Sendable {
    public let permission: SwooshPermission
    public let state: PermissionState
    public let updatedAt: Date?

    public init(permission: SwooshPermission, state: PermissionState, updatedAt: Date? = nil) {
        self.permission = permission
        self.state = state
        self.updatedAt = updatedAt
    }
}

// ── permissions.get ───────────────────────────────────────────────

public struct PermissionGetInput: Codable, Sendable {
    public let permission: SwooshPermission

    public init(permission: SwooshPermission) {
        self.permission = permission
    }
}

public struct PermissionGetOutput: Codable, Sendable {
    public let entry: PermissionEntry

    public init(entry: PermissionEntry) {
        self.entry = entry
    }
}

// ── permissions.request ───────────────────────────────────────────

public struct PermissionRequestInput: Codable, Sendable {
    public let permission: SwooshPermission
    public let reason: String
    public let requestedForTool: String?

    public init(permission: SwooshPermission, reason: String, requestedForTool: String? = nil) {
        self.permission = permission
        self.reason = reason
        self.requestedForTool = requestedForTool
    }
}

public struct PermissionRequestOutput: Codable, Sendable {
    public let requestID: String
    public let state: PermissionState

    public init(requestID: String, state: PermissionState) {
        self.requestID = requestID
        self.state = state
    }
}

// ── approvals.list_pending ────────────────────────────────────────

public struct ListPendingApprovalsInput: Codable, Sendable {
    public init() {}
}

public struct ListPendingApprovalsOutput: Codable, Sendable {
    public let approvals: [ToolApprovalRequest]

    public init(approvals: [ToolApprovalRequest]) {
        self.approvals = approvals
    }
}

// ── approvals.resolve ─────────────────────────────────────────────

public struct ResolveApprovalInput: Codable, Sendable {
    public let approvalID: String
    public let decision: ApprovalDecision
    public let reason: String?

    public init(approvalID: String, decision: ApprovalDecision, reason: String? = nil) {
        self.approvalID = approvalID
        self.decision = decision
        self.reason = reason
    }
}

public struct ResolveApprovalOutput: Codable, Sendable {
    public let approvalID: String
    public let resolved: Bool

    public init(approvalID: String, resolved: Bool) {
        self.approvalID = approvalID
        self.resolved = resolved
    }
}

// ═══════════════════════════════════════════════════════════════════
