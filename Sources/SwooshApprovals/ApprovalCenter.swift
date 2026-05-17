// SwooshApprovals/ApprovalCenter.swift — Approval center (0.4B)
//
// Manages the approval queue for risky tool calls.
// Only human-origin commands may resolve approvals.
// The model cannot approve its own tool calls.

import Foundation
import SwooshTools

// MARK: - Approval status

public enum ApprovalStatus: String, Codable, Sendable {
    case pending
    case approvedOnce
    case approvedForSession
    case denied
    case expired
}

// MARK: - Approval request record

public struct ApprovalRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let toolName: String
    public let risk: ToolRisk
    public let permission: SwooshPermission
    public let inputPreview: String
    public let origin: ToolCallOrigin
    public var status: ApprovalStatus
    public let createdAt: Date
    public var resolvedAt: Date?
    public var resolvedBy: ToolCallOrigin?
    public var denyReason: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        toolName: String,
        risk: ToolRisk,
        permission: SwooshPermission,
        inputPreview: String,
        origin: ToolCallOrigin,
        status: ApprovalStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.risk = risk
        self.permission = permission
        self.inputPreview = inputPreview
        self.origin = origin
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Approval errors

public enum ApprovalError: Error, Sendable {
    case modelCannotResolveHumanApproval
    case approvalNotFound(String)
    case alreadyResolved(String)
}

// MARK: - Approval store protocol

public protocol ApprovalStoring: Sendable {
    func save(_ approval: ApprovalRecord) async throws
    func get(id: String) async -> ApprovalRecord?
    func listPending(sessionID: String?) async -> [ApprovalRecord]
    func resolve(id: String, status: ApprovalStatus, resolvedBy: ToolCallOrigin, reason: String?) async throws
    func isApprovedForSession(toolName: String, sessionID: String) async -> Bool
}

// MARK: - In-memory approval store

public actor InMemoryApprovalStore: ApprovalStoring {
    private var records: [String: ApprovalRecord] = [:]

    public init() {}

    public func save(_ approval: ApprovalRecord) {
        records[approval.id] = approval
    }

    public func get(id: String) -> ApprovalRecord? {
        records[id]
    }

    public func listPending(sessionID: String?) -> [ApprovalRecord] {
        records.values
            .filter { $0.status == .pending }
            .filter { sessionID == nil || $0.sessionID == sessionID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func resolve(id: String, status: ApprovalStatus, resolvedBy: ToolCallOrigin, reason: String?) throws {
        guard var record = records[id] else {
            throw ApprovalError.approvalNotFound(id)
        }
        guard record.status == .pending else {
            throw ApprovalError.alreadyResolved(id)
        }
        record.status = status
        record.resolvedAt = Date()
        record.resolvedBy = resolvedBy
        record.denyReason = reason
        records[id] = record
    }

    public func isApprovedForSession(toolName: String, sessionID: String) -> Bool {
        records.values.contains { record in
            record.toolName == toolName &&
            record.sessionID == sessionID &&
            record.status == .approvedForSession
        }
    }
}

// MARK: - Approval center actor

/// Manages approval lifecycle. Implements ApprovalRequesting from SwooshTools.
public actor ApprovalCenter: ApprovalRequesting {
    private let store: any ApprovalStoring
    private let audit: any AuditLogging

    public init(store: any ApprovalStoring, audit: any AuditLogging) {
        self.store = store
        self.audit = audit
    }

    // MARK: - ApprovalRequesting conformance

    public func requireApproval(_ request: ToolApprovalRequest) async throws {
        // Check if already approved for session
        if await store.isApprovedForSession(toolName: request.toolName, sessionID: request.sessionID) {
            return // Session-level approval exists, proceed
        }

        // Create a pending approval record
        let record = ApprovalRecord(
            id: request.id,
            sessionID: request.sessionID,
            toolName: request.toolName,
            risk: request.risk,
            permission: .deviceProfileRead, // placeholder; real permission comes from descriptor
            inputPreview: request.inputPreview,
            origin: .model,
            status: .pending
        )

        try await store.save(record)
        try await audit.append(AuditEntry(
            kind: .approvalGranted,
            toolName: request.toolName,
            sessionID: request.sessionID,
            detail: "Approval requested for \(request.toolName) (risk: \(request.risk.rawValue))",
            success: true
        ))

        // Throw pendingApproval so the agent loop can stop and inform the user
        throw ToolError.pendingApproval(request.id)
    }

    public func listPending() async -> [ToolApprovalRequest] {
        let records = await store.listPending(sessionID: nil)
        return records.map { record in
            ToolApprovalRequest(
                id: record.id,
                toolName: record.toolName,
                risk: record.risk,
                inputPreview: record.inputPreview,
                sessionID: record.sessionID,
                createdAt: record.createdAt
            )
        }
    }

    public func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {
        let status: ApprovalStatus
        switch decision {
        case .approveOnce:       status = .approvedOnce
        case .approveForSession: status = .approvedForSession
        case .deny:              status = .denied
        }

        try await store.resolve(id: id, status: status, resolvedBy: .human, reason: reason)

        let auditKind: AuditEntryKind = decision == .deny ? .approvalDenied : .approvalGranted
        try await audit.append(AuditEntry(
            kind: auditKind,
            detail: "Approval \(id) resolved: \(decision.rawValue)\(reason.map { " — \($0)" } ?? "")"
        ))
    }

    // MARK: - Human resolution

    /// Resolve an approval. Only human-origin callers may resolve.
    public func resolveByHuman(
        id: String,
        decision: ApprovalDecision,
        origin: ToolCallOrigin,
        reason: String? = nil
    ) async throws {
        guard origin.canResolveHumanOnlyApproval else {
            throw ApprovalError.modelCannotResolveHumanApproval
        }
        try await resolve(id: id, decision: decision, reason: reason)
    }

    // MARK: - Query

    public func getApproval(id: String) async -> ApprovalRecord? {
        await store.get(id: id)
    }

    public func allPending(sessionID: String? = nil) async -> [ApprovalRecord] {
        await store.listPending(sessionID: sessionID)
    }
}
