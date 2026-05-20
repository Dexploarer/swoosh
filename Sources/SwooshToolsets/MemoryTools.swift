// SwooshToolsets/MemoryTools.swift — Memory & Vault toolset implementations
import Foundation
import SwooshTools

// ── memory.list_approved ──────────────────────────────────────────
public struct ListApprovedMemoriesTool: SwooshTool {
    public typealias Input = ListApprovedMemoriesInput; public typealias Output = ListApprovedMemoriesOutput
    public static let name: ToolName = "memory.list_approved"
    public static let displayName = "List Approved Memories"; public static let description = "List approved memories"
    public static let permission = SwooshPermission.toolRead; public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ListApprovedMemoriesOutput(
            memories: try await dependencies.memoryStore.listApproved(category: input.category, limit: input.limit)
        )
    }
}

// ── memory.search_approved ────────────────────────────────────────
public struct SearchApprovedMemoriesTool: SwooshTool {
    public typealias Input = SearchApprovedMemoriesInput; public typealias Output = SearchApprovedMemoriesOutput
    public static let name: ToolName = "memory.search_approved"
    public static let displayName = "Search Memories"; public static let description = "Search approved memories"
    public static let permission = SwooshPermission.toolRead; public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        SearchApprovedMemoriesOutput(
            results: try await dependencies.memoryStore.searchApproved(
                query: input.query,
                category: input.category,
                limit: input.limit
            )
        )
    }
}

// ── memory.get_approved ───────────────────────────────────────────
public struct GetApprovedMemoryTool: SwooshTool {
    public typealias Input = GetApprovedMemoryInput; public typealias Output = GetApprovedMemoryOutput
    public static let name: ToolName = "memory.get_approved"
    public static let displayName = "Get Memory"; public static let description = "Get one approved memory"
    public static let permission = SwooshPermission.toolRead; public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        GetApprovedMemoryOutput(memory: try await dependencies.memoryStore.getApproved(id: input.memoryID))
    }
}

// ── vault.list_candidates ─────────────────────────────────────────
public struct ListCandidatesTool: SwooshTool {
    public typealias Input = ListCandidatesInput; public typealias Output = ListCandidatesOutput
    public static let name: ToolName = "vault.list_candidates"
    public static let displayName = "List Candidates"; public static let description = "List pending memory candidates"
    public static let permission = SwooshPermission.toolRead; public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ListCandidatesOutput(
            candidates: try await dependencies.memoryStore.listCandidates(status: input.status, limit: input.limit)
        )
    }
}

// ── vault.get_candidate ───────────────────────────────────────────
public struct GetCandidateTool: SwooshTool {
    public typealias Input = GetCandidateInput; public typealias Output = GetCandidateOutput
    public static let name: ToolName = "vault.get_candidate"
    public static let displayName = "Get Candidate"; public static let description = "Inspect candidate and evidence"
    public static let permission = SwooshPermission.toolRead; public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        GetCandidateOutput(candidate: try await dependencies.memoryStore.getCandidate(id: input.candidateID))
    }
}

// ── vault.propose_candidate ───────────────────────────────────────
public struct ProposeCandidateTool: SwooshTool {
    public typealias Input = ProposeMemoryCandidateInput; public typealias Output = ProposeMemoryCandidateOutput
    public static let name: ToolName = "vault.propose_candidate"
    public static let displayName = "Propose Memory"; public static let description = "Propose a memory candidate"
    public static let permission = SwooshPermission.memoryWrite; public static let risk = ToolRisk.low
    public static let approval = ApprovalPolicy.askFirstTime; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let id = try await dependencies.memoryStore.propose(input)
        try await dependencies.audit.append(AuditEntry(kind: .memoryProposed, detail: "Proposed: \(input.text.prefix(80))"))
        return ProposeMemoryCandidateOutput(candidateID: id, status: .pending)
    }
}

// ── vault.approve_candidate (humanOnly) ───────────────────────────
public struct ApproveCandidateTool: SwooshTool {
    public typealias Input = ApproveMemoryCandidateInput; public typealias Output = ApproveMemoryCandidateOutput
    public static let name: ToolName = "vault.approve_candidate"
    public static let displayName = "Approve Memory"; public static let description = "Approve candidate into memory"
    public static let permission = SwooshPermission.memoryWrite; public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let memID = try await dependencies.memoryStore.approve(
            candidateID: input.candidateID,
            finalText: input.finalText
        )
        try await dependencies.audit.append(AuditEntry(kind: .memoryApproved, detail: "Approved candidate \(input.candidateID)"))
        return ApproveMemoryCandidateOutput(approvedMemoryID: memID)
    }
}

// ── vault.reject_candidate (humanOnly) ────────────────────────────
public struct RejectCandidateTool: SwooshTool {
    public typealias Input = RejectMemoryCandidateInput; public typealias Output = RejectMemoryCandidateOutput
    public static let name: ToolName = "vault.reject_candidate"
    public static let displayName = "Reject Memory"; public static let description = "Reject candidate"
    public static let permission = SwooshPermission.memoryWrite; public static let risk = ToolRisk.low
    public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await dependencies.memoryStore.reject(candidateID: input.candidateID, reason: input.reason)
        try await dependencies.audit.append(AuditEntry(kind: .memoryRejected, detail: "Rejected candidate \(input.candidateID)"))
        return RejectMemoryCandidateOutput(candidateID: input.candidateID, status: .rejected)
    }
}

// ── vault.edit_candidate (humanOnly) ──────────────────────────────
public struct EditCandidateTool: SwooshTool {
    public typealias Input = EditMemoryCandidateInput; public typealias Output = EditMemoryCandidateOutput
    public static let name: ToolName = "vault.edit_candidate"
    public static let displayName = "Edit Candidate"; public static let description = "Edit pending candidate"
    public static let permission = SwooshPermission.memoryWrite; public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.memory
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await dependencies.memoryStore.edit(
            candidateID: input.candidateID,
            newText: input.newText,
            newCategory: input.newCategory,
            newSensitivity: input.newSensitivity
        )
        try await dependencies.audit.append(AuditEntry(kind: .memoryEdited, detail: "Edited candidate \(input.candidateID)"))
        return EditMemoryCandidateOutput(candidateID: input.candidateID, status: .edited)
    }
}
