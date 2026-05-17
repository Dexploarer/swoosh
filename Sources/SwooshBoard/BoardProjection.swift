// SwooshBoard/BoardProjection.swift — 0.7A Board Projection
//
// Auto-creates/updates board cards from runtime events.
// Does NOT execute actions. Only visualizes state.
// Projection methods are internal/systemOnly — model cannot call them.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Projection actor
// ═══════════════════════════════════════════════════════════════════

public actor BoardProjection {
    private let store: any BoardStoring
    private let boardID: String
    private let redactor: BoardContentRedactor
    private let systemActor = BoardAssignee(id: "system", kind: .system, displayName: "Swoosh")

    public init(store: any BoardStoring, boardID: String, redactor: BoardContentRedactor = BoardContentRedactor()) {
        self.store = store; self.boardID = boardID; self.redactor = redactor
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Workflow run projection
    // ═══════════════════════════════════════════════════════════════

    public func projectWorkflowRun(
        runID: String, workflowID: String, workflowName: String,
        status: WorkflowRunProjectionStatus
    ) async throws {
        let cardStatus = mapWorkflowStatus(status)
        let priority: BoardCardPriority = status == .failed ? .high : .normal

        if var existing = try await findCardBySource(runID: runID, kind: .workflowRun) {
            existing.status = cardStatus
            existing.priority = priority
            existing.updatedAt = Date()
            try await store.updateCard(existing)
            try await addEvent(cardID: existing.id, type: .cardUpdated, message: "Workflow run \(status.rawValue)")
        } else {
            let card = BoardCard(
                boardID: boardID, title: workflowName,
                summary: "Workflow run \(runID)",
                kind: .workflowRun, status: cardStatus, priority: priority,
                source: BoardCardSource(kind: .workflowRun, workflowID: workflowID, runID: runID)
            )
            try await store.saveCard(card)
            try await addEvent(cardID: card.id, type: .cardCreated, message: "Workflow run started")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Approval projection
    // ═══════════════════════════════════════════════════════════════

    public func projectApproval(
        approvalID: String, title: String, summary: String, risk: ToolRisk,
        status: ApprovalProjectionStatus, gateID: String? = nil, runID: String? = nil
    ) async throws {
        let cardStatus = mapApprovalStatus(status)
        let priority = mapRiskPriority(risk)
        let redactedSummary = redactor.redact(summary)

        if var existing = try await findCardBySource(approvalID: approvalID, kind: .approval) {
            existing.status = cardStatus
            existing.updatedAt = Date()
            try await store.updateCard(existing)
            try await addEvent(cardID: existing.id, type: .cardUpdated, message: "Approval \(status.rawValue)")
        } else {
            let card = BoardCard(
                boardID: boardID, title: title,
                summary: redactedSummary,
                kind: .approval, status: cardStatus, priority: priority,
                source: BoardCardSource(kind: .approval, runID: runID, approvalID: approvalID)
            )
            try await store.saveCard(card)
            try await addEvent(cardID: card.id, type: .cardCreated, message: "Approval pending")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Trigger event projection
    // ═══════════════════════════════════════════════════════════════

    public func projectTriggerEvent(
        triggerEventID: String, triggerID: String, workflowName: String,
        triggerKind: String, status: TriggerProjectionStatus
    ) async throws {
        let cardStatus = mapTriggerStatus(status)
        let card = BoardCard(
            boardID: boardID, title: "Trigger: \(triggerKind) for \(workflowName)",
            summary: "Trigger event \(triggerEventID)",
            kind: .triggerEvent, status: cardStatus,
            source: BoardCardSource(kind: .trigger, triggerID: triggerID, triggerEventID: triggerEventID)
        )
        try await store.saveCard(card)
        try await addEvent(cardID: card.id, type: .triggerEventLinked, message: "Trigger event \(status.rawValue)")
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Memory candidate projection
    // ═══════════════════════════════════════════════════════════════

    public func projectMemoryCandidate(
        candidateID: String, redactedSummary: String,
        status: MemoryProjectionStatus
    ) async throws {
        let cardStatus = mapMemoryStatus(status)
        let card = BoardCard(
            boardID: boardID, title: "Memory review",
            summary: redactor.redact(redactedSummary),
            kind: .memoryReview, status: cardStatus,
            source: BoardCardSource(kind: .memory, memoryCandidateID: candidateID)
        )
        try await store.saveCard(card)
        try await addEvent(cardID: card.id, type: .cardCreated, message: "Memory candidate \(status.rawValue)")
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Session task projection
    // ═══════════════════════════════════════════════════════════════

    public func projectSessionTask(
        title: String, summary: String?, priority: BoardCardPriority,
        kind: BoardCardKind, sessionID: String
    ) async throws {
        let card = BoardCard(
            boardID: boardID, title: title, summary: summary,
            kind: kind, status: .inbox, priority: priority,
            source: BoardCardSource(kind: .session, sessionID: sessionID)
        )
        try await store.saveCard(card)
        try await addEvent(cardID: card.id, type: .cardCreated, message: "Card created from session")
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ═══════════════════════════════════════════════════════════════

    private func findCardBySource(runID: String? = nil, approvalID: String? = nil, kind: BoardCardKind) async throws -> BoardCard? {
        let cards = try await store.listCards(boardID: boardID, filter: BoardCardFilter(kind: kind))
        return cards.first { card in
            if let r = runID, card.source.runID == r { return true }
            if let a = approvalID, card.source.approvalID == a { return true }
            return false
        }
    }

    private func addEvent(cardID: String, type: BoardEventType, message: String) async throws {
        let event = BoardEvent(cardID: cardID, boardID: boardID, type: type, actor: systemActor, message: message)
        try await store.saveEvent(event)
    }

    private func mapWorkflowStatus(_ s: WorkflowRunProjectionStatus) -> BoardCardStatus07A {
        switch s {
        case .running: return .running
        case .pausedForApproval: return .needsApproval
        case .completed: return .done
        case .failed: return .blocked
        }
    }

    private func mapApprovalStatus(_ s: ApprovalProjectionStatus) -> BoardCardStatus07A {
        switch s {
        case .pending: return .needsApproval
        case .approved: return .done
        case .denied: return .blocked
        case .expired: return .blocked
        }
    }

    private func mapTriggerStatus(_ s: TriggerProjectionStatus) -> BoardCardStatus07A {
        switch s {
        case .detected, .queued: return .running
        case .rejected, .failed: return .blocked
        case .completed: return .done
        }
    }

    private func mapMemoryStatus(_ s: MemoryProjectionStatus) -> BoardCardStatus07A {
        switch s {
        case .pending: return .review
        case .approved, .rejected: return .done
        }
    }

    private func mapRiskPriority(_ risk: ToolRisk) -> BoardCardPriority {
        switch risk {
        case .readOnly, .low: return .normal
        case .medium: return .high
        case .high, .critical: return .urgent
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Projection status enums (decoupled from runtime types)
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowRunProjectionStatus: String, Codable, Sendable {
    case running, pausedForApproval, completed, failed
}

public enum ApprovalProjectionStatus: String, Codable, Sendable {
    case pending, approved, denied, expired
}

public enum TriggerProjectionStatus: String, Codable, Sendable {
    case detected, queued, rejected, failed, completed
}

public enum MemoryProjectionStatus: String, Codable, Sendable {
    case pending, approved, rejected
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Content redactor
// ═══════════════════════════════════════════════════════════════════

public struct BoardContentRedactor: Sendable {
    private static let sensitivePatterns = [
        "-----BEGIN", "PRIVATE KEY", "sk_", "xprv", "xpub",
        "seed:", "mnemonic:", "cookie:", "session_token",
        "password:", "secret:", "Bearer ",
    ]
    private let maxPreviewLength: Int

    public init(maxPreviewLength: Int = 200) { self.maxPreviewLength = maxPreviewLength }

    public func redact(_ text: String) -> String {
        var value = text
        for pattern in Self.sensitivePatterns {
            if value.contains(pattern) { value = value.replacingOccurrences(of: pattern, with: "[REDACTED]") }
        }
        if value.count > maxPreviewLength {
            value = String(value.prefix(maxPreviewLength - 1)) + "…"
        }
        return value
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Board safety: card actions do NOT execute runtime actions
// ═══════════════════════════════════════════════════════════════════

/// Utility to validate board card operations respect safety boundaries.
public struct BoardSafetyPolicy: Sendable {
    public init() {}

    /// Returns true if the card is linked to an active approval.
    /// Moving this card to .done will NOT resolve the approval.
    public func requiresApprovalRouting(_ card: BoardCard) -> Bool {
        card.kind == .approval && card.source.approvalID != nil
    }

    /// Explanation for /card why
    public func whyExplanation(_ card: BoardCard) -> String {
        var lines: [String] = []
        lines.append("Card: \(card.title)")
        lines.append("Kind: \(card.kind.rawValue)")
        lines.append("Status: \(card.status.rawValue)")
        lines.append("Source: \(card.source.kind.rawValue)")

        if let runID = card.source.runID { lines.append("Linked workflow run: \(runID)") }
        if let approvalID = card.source.approvalID { lines.append("Linked approval: \(approvalID)") }
        if let triggerID = card.source.triggerID { lines.append("Linked trigger: \(triggerID)") }
        if let memoryID = card.source.memoryCandidateID { lines.append("Linked memory candidate: \(memoryID)") }

        if requiresApprovalRouting(card) {
            lines.append("")
            lines.append("Safety: Moving this card to Done will NOT approve the underlying action.")
            lines.append("Use /approval approve <approval-id> to approve through the Approval Center.")
        }
        return lines.joined(separator: "\n")
    }
}
