// SwooshTools/CoreToolTypes.swift — Input/Output types for Core, Memory, Vault,
// Permissions, Approvals, Scout, and Audit toolsets.
//
// Every tool has typed input and output. No loose JSON blobs.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Core tools
// ═══════════════════════════════════════════════════════════════════

// core.status
public struct CoreStatusInput: Codable, Sendable {}

public struct CoreStatusOutput: Codable, Sendable {
    public let version: String
    public let mode: String
    public let statePlane: String
    public let approvedMemoryCount: Int
    public let pendingMemoryCandidateCount: Int
    public let enabledToolsets: [String]

    public init(
        version: String,
        mode: String,
        statePlane: String,
        approvedMemoryCount: Int,
        pendingMemoryCandidateCount: Int,
        enabledToolsets: [String]
    ) {
        self.version = version
        self.mode = mode
        self.statePlane = statePlane
        self.approvedMemoryCount = approvedMemoryCount
        self.pendingMemoryCandidateCount = pendingMemoryCandidateCount
        self.enabledToolsets = enabledToolsets
    }
}

// core.explain_context
public struct ExplainContextInput: Codable, Sendable {
    public let sessionID: String
    public let messageID: String?

    public init(sessionID: String, messageID: String? = nil) {
        self.sessionID = sessionID
        self.messageID = messageID
    }
}

public struct ExplainContextOutput: Codable, Sendable {
    public let approvedMemoryIDs: [String]
    public let setupReportID: String?
    public let permissionSummary: String
    public let excludedSources: [String]
    public let modelUsed: String?

    public init(
        approvedMemoryIDs: [String],
        setupReportID: String?,
        permissionSummary: String,
        excludedSources: [String],
        modelUsed: String?
    ) {
        self.approvedMemoryIDs = approvedMemoryIDs
        self.setupReportID = setupReportID
        self.permissionSummary = permissionSummary
        self.excludedSources = excludedSources
        self.modelUsed = modelUsed
    }
}

// core.list_toolsets
public struct ListToolsetsInput: Codable, Sendable {
    public init() {}
}

public struct ListToolsetsOutput: Codable, Sendable {
    public let toolsets: [String]

    public init(toolsets: [String]) {
        self.toolsets = toolsets
    }
}

// core.list_tools
public struct ListToolsInput: Codable, Sendable {
    public let toolset: String?

    public init(toolset: String? = nil) {
        self.toolset = toolset
    }
}

public struct ListToolsOutput: Codable, Sendable {
    public let tools: [ToolDescriptor]

    public init(tools: [ToolDescriptor]) {
        self.tools = tools
    }
}

// core.get_tool_schema
public struct GetToolSchemaInput: Codable, Sendable {
    public let toolName: String

    public init(toolName: String) {
        self.toolName = toolName
    }
}

public struct GetToolSchemaOutput: Codable, Sendable {
    public let descriptor: ToolDescriptor?

    public init(descriptor: ToolDescriptor?) {
        self.descriptor = descriptor
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Memory types
// ═══════════════════════════════════════════════════════════════════

public struct ApprovedMemory: Codable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let category: MemoryCategory
    public let sensitivity: Sensitivity
    public let confidence: Double
    public let createdAt: Date
    public let lastUsedAt: Date?

    public init(
        id: String,
        text: String,
        category: MemoryCategory,
        sensitivity: Sensitivity = .normal,
        confidence: Double = 1.0,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public enum Sensitivity: String, Codable, Sendable {
    case normal
    case sensitive
    case secret
}

public struct EvidencePointer: Codable, Sendable {
    public let sourceID: String
    public let recordID: String?
    public let sessionID: String?
    public let description: String

    public init(sourceID: String, recordID: String? = nil, sessionID: String? = nil, description: String) {
        self.sourceID = sourceID
        self.recordID = recordID
        self.sessionID = sessionID
        self.description = description
    }
}

public enum CandidateStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case edited
}

public struct MemoryCandidate: Codable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let category: MemoryCategory
    public let sensitivity: Sensitivity
    public let confidence: Double
    public let evidence: [EvidencePointer]
    public let status: CandidateStatus
    public let createdAt: Date

    public init(
        id: String,
        text: String,
        category: MemoryCategory,
        sensitivity: Sensitivity,
        confidence: Double,
        evidence: [EvidencePointer],
        status: CandidateStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.evidence = evidence
        self.status = status
        self.createdAt = createdAt
    }
}

// ── memory.list_approved ──────────────────────────────────────────

public struct ListApprovedMemoriesInput: Codable, Sendable {
    public let category: MemoryCategory?
    public let limit: Int?

    public init(category: MemoryCategory? = nil, limit: Int? = nil) {
        self.category = category
        self.limit = limit
    }
}

public struct ListApprovedMemoriesOutput: Codable, Sendable {
    public let memories: [ApprovedMemory]

    public init(memories: [ApprovedMemory]) {
        self.memories = memories
    }
}

// ── memory.search_approved ────────────────────────────────────────

public struct SearchApprovedMemoriesInput: Codable, Sendable {
    public let query: String
    public let category: MemoryCategory?
    public let limit: Int?

    public init(query: String, category: MemoryCategory? = nil, limit: Int? = nil) {
        self.query = query
        self.category = category
        self.limit = limit
    }
}

public struct SearchApprovedMemoriesOutput: Codable, Sendable {
    public let results: [ApprovedMemorySearchResult]

    public init(results: [ApprovedMemorySearchResult]) {
        self.results = results
    }
}

public struct ApprovedMemorySearchResult: Codable, Sendable {
    public let memory: ApprovedMemory
    public let score: Double
    public let reason: String

    public init(memory: ApprovedMemory, score: Double, reason: String) {
        self.memory = memory
        self.score = score
        self.reason = reason
    }
}

// ── memory.get_approved ───────────────────────────────────────────

public struct GetApprovedMemoryInput: Codable, Sendable {
    public let memoryID: String

    public init(memoryID: String) {
        self.memoryID = memoryID
    }
}

public struct GetApprovedMemoryOutput: Codable, Sendable {
    public let memory: ApprovedMemory?

    public init(memory: ApprovedMemory?) {
        self.memory = memory
    }
}

// ═══════════════════════════════════════════════════════════════════
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
// MARK: - Scout tools
// ═══════════════════════════════════════════════════════════════════

// ── scout.list_sources ────────────────────────────────────────────

public struct ScoutListSourcesInput: Codable, Sendable {
    public init() {}
}

public struct ScoutListSourcesOutput: Codable, Sendable {
    public let sources: [ScoutSourceInfo]

    public init(sources: [ScoutSourceInfo]) {
        self.sources = sources
    }
}

public struct ScoutSourceInfo: Codable, Sendable {
    public let sourceID: String
    public let displayName: String
    public let kind: String
    public let enabled: Bool

    public init(sourceID: String, displayName: String, kind: String, enabled: Bool) {
        self.sourceID = sourceID
        self.displayName = displayName
        self.kind = kind
        self.enabled = enabled
    }
}

// ── scout.status ──────────────────────────────────────────────────

public struct ScoutStatusInput: Codable, Sendable {
    public init() {}
}

public struct ScoutStatusOutput: Codable, Sendable {
    public let lastScanDate: Date?
    public let recordCount: Int
    public let candidateCount: Int

    public init(lastScanDate: Date?, recordCount: Int, candidateCount: Int) {
        self.lastScanDate = lastScanDate
        self.recordCount = recordCount
        self.candidateCount = candidateCount
    }
}

// ── scout.run ─────────────────────────────────────────────────────

public struct ScoutRunInput: Codable, Sendable {
    public let sourceIDs: [String]
    public let selectedFolderBookmarks: [String]
    public let dryRun: Bool

    public init(sourceIDs: [String], selectedFolderBookmarks: [String] = [], dryRun: Bool = false) {
        self.sourceIDs = sourceIDs
        self.selectedFolderBookmarks = selectedFolderBookmarks
        self.dryRun = dryRun
    }
}

public struct ScoutRunOutput: Codable, Sendable {
    public let scanID: String
    public let recordsCreated: Int
    public let candidatesCreated: Int
    public let skippedSources: [SkippedScoutSource]

    public init(scanID: String, recordsCreated: Int, candidatesCreated: Int, skippedSources: [SkippedScoutSource]) {
        self.scanID = scanID
        self.recordsCreated = recordsCreated
        self.candidatesCreated = candidatesCreated
        self.skippedSources = skippedSources
    }
}

public struct SkippedScoutSource: Codable, Sendable {
    public let sourceID: String
    public let reason: String

    public init(sourceID: String, reason: String) {
        self.sourceID = sourceID
        self.reason = reason
    }
}

// ── scout.get_report ──────────────────────────────────────────────

public struct ScoutGetReportInput: Codable, Sendable {
    public let scanID: String?

    public init(scanID: String? = nil) {
        self.scanID = scanID
    }
}

public struct ScoutGetReportOutput: Codable, Sendable {
    public let reportMarkdown: String
    public let scanID: String?

    public init(reportMarkdown: String, scanID: String?) {
        self.reportMarkdown = reportMarkdown
        self.scanID = scanID
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Audit tools
// ═══════════════════════════════════════════════════════════════════

// ── audit.tail ────────────────────────────────────────────────────

public struct AuditTailInput: Codable, Sendable {
    public let limit: Int?
    public let eventTypes: [String]?

    public init(limit: Int? = nil, eventTypes: [String]? = nil) {
        self.limit = limit
        self.eventTypes = eventTypes
    }
}

public struct AuditTailOutput: Codable, Sendable {
    public let events: [AuditEntry]

    public init(events: [AuditEntry]) {
        self.events = events
    }
}

// ── audit.search ──────────────────────────────────────────────────

public struct AuditSearchInput: Codable, Sendable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct AuditSearchOutput: Codable, Sendable {
    public let events: [AuditEntry]

    public init(events: [AuditEntry]) {
        self.events = events
    }
}

// ── audit.get_event ───────────────────────────────────────────────

public struct AuditGetEventInput: Codable, Sendable {
    public let eventID: String

    public init(eventID: String) {
        self.eventID = eventID
    }
}

public struct AuditGetEventOutput: Codable, Sendable {
    public let event: AuditEntry?

    public init(event: AuditEntry?) {
        self.event = event
    }
}
