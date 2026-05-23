// SwooshClient/WireTypes+Audit.swift — 0.4A Audit + Approval wire types
//
// Wire format for `GET /api/audit`, `GET /api/approvals`, and
// `POST /api/approvals/{id}/resolve`. Audit entries are read-only;
// approval decisions are the user's escape hatch for the firewall.

import Foundation

public struct AuditEventSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let timestamp: Date
    public let kind: String
    public let toolName: String?
    public let sessionID: String?
    public let detail: String
    public let success: Bool

    public init(
        id: String,
        timestamp: Date,
        kind: String,
        toolName: String?,
        sessionID: String?,
        detail: String,
        success: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.toolName = toolName
        self.sessionID = sessionID
        self.detail = detail
        self.success = success
    }
}

public struct AuditEventsResponse: Codable, Sendable, Equatable {
    public let events: [AuditEventSummary]
    public let generatedAt: Date

    public init(events: [AuditEventSummary], generatedAt: Date = Date()) {
        self.events = events
        self.generatedAt = generatedAt
    }
}

public struct ApprovalSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let sessionID: String
    public let toolName: String
    public let risk: String
    public let permission: String
    public let inputPreview: String
    public let status: String
    public let createdAt: Date

    public init(
        id: String,
        sessionID: String,
        toolName: String,
        risk: String,
        permission: String,
        inputPreview: String,
        status: String,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.risk = risk
        self.permission = permission
        self.inputPreview = inputPreview
        self.status = status
        self.createdAt = createdAt
    }
}

public struct ApprovalsResponse: Codable, Sendable, Equatable {
    public let pending: [ApprovalSummary]
    public let history: [ApprovalSummary]
    public let generatedAt: Date

    public init(pending: [ApprovalSummary], history: [ApprovalSummary] = [], generatedAt: Date = Date()) {
        self.pending = pending
        self.history = history
        self.generatedAt = generatedAt
    }
}

public struct ApprovalResolveRequest: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable {
        case approveOnce
        case approveForSession
        case deny
    }

    public let decision: Decision
    public let reason: String?

    public init(decision: Decision, reason: String? = nil) {
        self.decision = decision
        self.reason = reason
    }
}

public struct ApprovalResolveResponse: Codable, Sendable, Equatable {
    public let approval: ApprovalSummary
    public let message: String

    public init(approval: ApprovalSummary, message: String) {
        self.approval = approval
        self.message = message
    }
}
