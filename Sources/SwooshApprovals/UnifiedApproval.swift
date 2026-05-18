// SwooshApprovals/UnifiedApproval.swift — 0.6C Notifications + Approval UX
//
// Unified approval model that normalizes tool calls, workflow gates,
// memory candidates, trigger arming, and runner control into a single inbox.
// Only human-origin decisions can resolve approvals.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Unified approval
// ═══════════════════════════════════════════════════════════════════

public struct UnifiedApproval: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: ApprovalKind06C
    public let title: String
    public let summary: String
    public let source: ApprovalSource
    public let risk: ToolRisk
    public var status: UnifiedApprovalStatus
    public let preview: ApprovalPreview06C
    public let allowedDecisions: [ApprovalDecisionKind06C]
    public let confirmationRequirement: ConfirmationRequirement
    public let expiresAt: Date?
    public let createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: String = UUID().uuidString, kind: ApprovalKind06C, title: String,
        summary: String, source: ApprovalSource, risk: ToolRisk,
        status: UnifiedApprovalStatus = .pending, preview: ApprovalPreview06C,
        allowedDecisions: [ApprovalDecisionKind06C] = [.approveOnce, .deny],
        confirmationRequirement: ConfirmationRequirement = .none,
        expiresAt: Date? = nil, createdAt: Date = Date(), resolvedAt: Date? = nil
    ) {
        self.id = id; self.kind = kind; self.title = title; self.summary = summary
        self.source = source; self.risk = risk; self.status = status; self.preview = preview
        self.allowedDecisions = allowedDecisions; self.confirmationRequirement = confirmationRequirement
        self.expiresAt = expiresAt; self.createdAt = createdAt; self.resolvedAt = resolvedAt
    }

    public func resolved(status: UnifiedApprovalStatus, resolvedAt: Date) -> UnifiedApproval {
        var copy = self; copy.status = status; copy.resolvedAt = resolvedAt; return copy
    }

    public var isExpired: Bool {
        if let exp = expiresAt { return Date() > exp }
        return false
    }
}

public enum ApprovalKind06C: String, Codable, Sendable {
    case toolCall, workflowGate, memoryCandidate, workflowEnablement, triggerArming, runnerControl
}

public enum UnifiedApprovalStatus: String, Codable, Sendable {
    case pending, approved, denied, expired, cancelled
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Source
// ═══════════════════════════════════════════════════════════════════

public struct ApprovalSource: Codable, Sendable {
    public let sessionID: String?
    public let workflowID: String?
    public let runID: String?
    public let stepID: String?
    public let gateID: String?
    public let toolCallID: String?
    public let triggerID: String?
    public let origin: ToolCallOrigin

    public init(
        sessionID: String? = nil, workflowID: String? = nil, runID: String? = nil,
        stepID: String? = nil, gateID: String? = nil, toolCallID: String? = nil,
        triggerID: String? = nil, origin: ToolCallOrigin = .system
    ) {
        self.sessionID = sessionID; self.workflowID = workflowID; self.runID = runID
        self.stepID = stepID; self.gateID = gateID; self.toolCallID = toolCallID
        self.triggerID = triggerID; self.origin = origin
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════

public struct ApprovalPreview06C: Codable, Sendable {
    public let humanSummary: String
    public let actionType: ApprovalActionType
    public let commandPreview: String?
    public let diffPreview: String?
    public let riskWarnings: [String]
    public let rollbackHint: String?

    public init(
        humanSummary: String, actionType: ApprovalActionType = .other,
        commandPreview: String? = nil, diffPreview: String? = nil,
        riskWarnings: [String] = [], rollbackHint: String? = nil
    ) {
        self.humanSummary = humanSummary; self.actionType = actionType
        self.commandPreview = commandPreview; self.diffPreview = diffPreview
        self.riskWarnings = riskWarnings; self.rollbackHint = rollbackHint
    }
}

public enum ApprovalActionType: String, Codable, Sendable {
    case runCommand, modifyFile, createGitCommit, buildTransaction
    case enableWorkflow, armTrigger, approveMemory, controlRunner, other
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Confirmation
// ═══════════════════════════════════════════════════════════════════

public enum ConfirmationRequirement: Codable, Sendable {
    case none
    case clickOnly
    case typeExact(String)
    case typeContains(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Decision
// ═══════════════════════════════════════════════════════════════════

public enum ApprovalDecisionKind06C: String, Codable, Sendable {
    case approveOnce, approveForSession, deny, cancel
}

public struct UnifiedApprovalDecision: Codable, Sendable {
    public let approvalID: String
    public let decision: ApprovalDecisionKind06C
    public let confirmationText: String?
    public let reason: String?
    public let decidedBy: ApprovalDecisionActor
    public let decidedAt: Date

    public init(
        approvalID: String, decision: ApprovalDecisionKind06C,
        confirmationText: String? = nil, reason: String? = nil,
        decidedBy: ApprovalDecisionActor = .human, decidedAt: Date = Date()
    ) {
        self.approvalID = approvalID; self.decision = decision
        self.confirmationText = confirmationText; self.reason = reason
        self.decidedBy = decidedBy; self.decidedAt = decidedAt
    }
}

public enum ApprovalDecisionActor: String, Codable, Sendable {
    case human
    // model, workflow, daemon CANNOT approve
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Expiration policy
// ═══════════════════════════════════════════════════════════════════

public struct ApprovalExpirationPolicy: Codable, Sendable {
    public let defaultTTLSeconds: Int
    public let highRiskTTLSeconds: Int
    public let criticalTTLSeconds: Int

    public static let `default` = ApprovalExpirationPolicy(
        defaultTTLSeconds: 3600, highRiskTTLSeconds: 900, criticalTTLSeconds: 300
    )

    public init(defaultTTLSeconds: Int, highRiskTTLSeconds: Int, criticalTTLSeconds: Int) {
        self.defaultTTLSeconds = defaultTTLSeconds; self.highRiskTTLSeconds = highRiskTTLSeconds
        self.criticalTTLSeconds = criticalTTLSeconds
    }

    public func ttl(for risk: ToolRisk) -> TimeInterval {
        switch risk {
        case .critical: return Double(criticalTTLSeconds)
        case .high: return Double(highRiskTTLSeconds)
        default: return Double(defaultTTLSeconds)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Grouping
// ═══════════════════════════════════════════════════════════════════

public struct ApprovalGroup: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let kind: ApprovalGroupKind
    public let approvals: [UnifiedApproval]
    public init(id: String = UUID().uuidString, title: String, kind: ApprovalGroupKind, approvals: [UnifiedApproval]) {
        self.id = id; self.title = title; self.kind = kind; self.approvals = approvals
    }
}

public enum ApprovalGroupKind: String, Codable, Sendable {
    case workflowRun, session, risk, kind, trigger
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Inbox store
// ═══════════════════════════════════════════════════════════════════

public protocol UnifiedApprovalStoring: Sendable {
    func save(_ approval: UnifiedApproval) async throws
    func update(_ approval: UnifiedApproval) async throws
    func get(id: String) async throws -> UnifiedApproval?
    func listPending() async throws -> [UnifiedApproval]
    func listHistory(limit: Int?) async throws -> [UnifiedApproval]
    func search(query: String) async throws -> [UnifiedApproval]
}

public actor InMemoryUnifiedApprovalStore: UnifiedApprovalStoring {
    private var approvals: [String: UnifiedApproval] = [:]
    public init() {}
    public func save(_ a: UnifiedApproval) { approvals[a.id] = a }
    public func update(_ a: UnifiedApproval) { approvals[a.id] = a }
    public func get(id: String) -> UnifiedApproval? { approvals[id] }
    public func listPending() -> [UnifiedApproval] {
        approvals.values.filter { $0.status == .pending && !$0.isExpired }
            .sorted { $0.createdAt > $1.createdAt }
    }
    public func listHistory(limit: Int?) -> [UnifiedApproval] {
        var r = approvals.values.filter { $0.status != .pending }
            .sorted { ($0.resolvedAt ?? $0.createdAt) > ($1.resolvedAt ?? $1.createdAt) }
        if let l = limit { r = Array(r.prefix(l)) }
        return r
    }
    public func search(query: String) -> [UnifiedApproval] {
        let q = query.lowercased()
        return approvals.values.filter { $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Approval inbox
// ═══════════════════════════════════════════════════════════════════

public actor ApprovalInbox {
    private let store: any UnifiedApprovalStoring
    public private(set) var lastSubmittedID: String?

    public init(store: any UnifiedApprovalStoring) { self.store = store }

    public func submit(_ approval: UnifiedApproval) async throws {
        try await store.save(approval)
        lastSubmittedID = approval.id
    }

    public func resolve(_ decision: UnifiedApprovalDecision) async throws -> UnifiedApproval {
        guard var approval = try await store.get(id: decision.approvalID) else {
            throw UnifiedApprovalError.approvalNotFound(decision.approvalID)
        }
        guard approval.status == .pending else {
            throw UnifiedApprovalError.alreadyResolved(decision.approvalID)
        }
        if approval.isExpired {
            approval.status = .expired; try await store.update(approval)
            throw UnifiedApprovalError.approvalExpired(decision.approvalID)
        }
        // Only human can resolve
        guard decision.decidedBy == .human else {
            throw UnifiedApprovalError.onlyHumanCanResolve
        }
        // Check confirmation requirement
        try validateConfirmation(decision, approval: approval)

        let newStatus: UnifiedApprovalStatus = (decision.decision == .deny || decision.decision == .cancel) ? .denied : .approved
        let resolved = approval.resolved(status: newStatus, resolvedAt: decision.decidedAt)
        try await store.update(resolved)
        return resolved
    }

    public func listPending() async throws -> [UnifiedApproval] {
        try await store.listPending()
    }

    public func listHistory(limit: Int? = nil) async throws -> [UnifiedApproval] {
        try await store.listHistory(limit: limit)
    }

    public func search(query: String) async throws -> [UnifiedApproval] {
        try await store.search(query: query)
    }

    public func get(id: String) async throws -> UnifiedApproval? {
        try await store.get(id: id)
    }

    public func groupByRisk(_ approvals: [UnifiedApproval]) -> [ApprovalGroup] {
        let grouped = Dictionary(grouping: approvals) { $0.risk }
        return grouped.map { risk, items in
            ApprovalGroup(title: "\(risk.rawValue) risk", kind: .risk, approvals: items)
        }.sorted { $0.title < $1.title }
    }

    private func validateConfirmation(_ decision: UnifiedApprovalDecision, approval: UnifiedApproval) throws {
        switch approval.confirmationRequirement {
        case .none: break
        case .clickOnly: break
        case .typeExact(let expected):
            guard decision.confirmationText == expected else {
                throw UnifiedApprovalError.confirmationRequired(expected)
            }
        case .typeContains(let substring):
            guard let text = decision.confirmationText, text.contains(substring) else {
                throw UnifiedApprovalError.confirmationRequired(substring)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
