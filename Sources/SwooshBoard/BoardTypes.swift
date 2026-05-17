// SwooshBoard/BoardTypes.swift — 0.7A Swoosh Board Types
//
// Durable, approval-aware task board model.
// Cards do NOT execute underlying actions — they reference and visualize them.
// All risky actions still go through ApprovalInbox / WorkflowExecutionEngine.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Board
// ═══════════════════════════════════════════════════════════════════

public struct Board07A: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var description: String?
    public var columns: [BoardColumn]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString, name: String = "Swoosh Board",
        description: String? = nil, columns: [BoardColumn] = BoardColumn.defaults,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.name = name; self.description = description
        self.columns = columns; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Column
// ═══════════════════════════════════════════════════════════════════

public struct BoardColumn: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var status: BoardCardStatus07A
    public var sortOrder: Int
    public var isSystem: Bool

    public init(id: String = UUID().uuidString, name: String, status: BoardCardStatus07A, sortOrder: Int, isSystem: Bool = true) {
        self.id = id; self.name = name; self.status = status; self.sortOrder = sortOrder; self.isSystem = isSystem
    }

    public static let defaults: [BoardColumn] = [
        BoardColumn(name: "Inbox", status: .inbox, sortOrder: 0),
        BoardColumn(name: "Ready", status: .ready, sortOrder: 1),
        BoardColumn(name: "Running", status: .running, sortOrder: 2),
        BoardColumn(name: "Needs Approval", status: .needsApproval, sortOrder: 3),
        BoardColumn(name: "Blocked", status: .blocked, sortOrder: 4),
        BoardColumn(name: "Review", status: .review, sortOrder: 5),
        BoardColumn(name: "Done", status: .done, sortOrder: 6),
        BoardColumn(name: "Archived", status: .archived, sortOrder: 7),
    ]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Card status
// ═══════════════════════════════════════════════════════════════════

public enum BoardCardStatus07A: String, Codable, Sendable {
    case inbox, ready, running, needsApproval, blocked, review, done, archived
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Card kind
// ═══════════════════════════════════════════════════════════════════

public enum BoardCardKind: String, Codable, Sendable {
    case manualTask, workflowRun, workflowStep, approval, triggerEvent
    case agentTask, humanReview, bug, codeChange, research
    case memoryReview, blockchainReview, systemNotice
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Card priority
// ═══════════════════════════════════════════════════════════════════

public enum BoardCardPriority: String, Codable, Sendable {
    case low, normal, high, urgent
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Assignee
// ═══════════════════════════════════════════════════════════════════

public struct BoardAssignee: Codable, Sendable, Hashable {
    public let id: String
    public let kind: BoardAssigneeKind
    public let displayName: String
    public init(id: String = UUID().uuidString, kind: BoardAssigneeKind = .human, displayName: String) {
        self.id = id; self.kind = kind; self.displayName = displayName
    }
}

public enum BoardAssigneeKind: String, Codable, Sendable, Hashable {
    case human, swoosh, workflow, system, external
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Card source
// ═══════════════════════════════════════════════════════════════════

public struct BoardCardSource: Codable, Sendable {
    public let kind: BoardCardSourceKind
    public let sessionID: String?
    public let workflowID: String?
    public let runID: String?
    public let stepRunID: String?
    public let approvalID: String?
    public let triggerID: String?
    public let triggerEventID: String?
    public let memoryCandidateID: String?
    public let toolCallID: String?

    public init(
        kind: BoardCardSourceKind = .manual, sessionID: String? = nil,
        workflowID: String? = nil, runID: String? = nil, stepRunID: String? = nil,
        approvalID: String? = nil, triggerID: String? = nil, triggerEventID: String? = nil,
        memoryCandidateID: String? = nil, toolCallID: String? = nil
    ) {
        self.kind = kind; self.sessionID = sessionID; self.workflowID = workflowID
        self.runID = runID; self.stepRunID = stepRunID; self.approvalID = approvalID
        self.triggerID = triggerID; self.triggerEventID = triggerEventID
        self.memoryCandidateID = memoryCandidateID; self.toolCallID = toolCallID
    }
}

public enum BoardCardSourceKind: String, Codable, Sendable {
    case manual, session, workflow, workflowRun, workflowStep
    case approval, trigger, memory, toolCall, system
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Board card
// ═══════════════════════════════════════════════════════════════════

public struct BoardCard: Codable, Sendable, Identifiable {
    public let id: String
    public let boardID: String
    public var title: String
    public var summary: String?
    public var kind: BoardCardKind
    public var status: BoardCardStatus07A
    public var priority: BoardCardPriority
    public var assignee: BoardAssignee?
    public var source: BoardCardSource
    public var links: [BoardLink]
    public var artifactIDs: [String]
    public var blockerIDs: [String]
    public var commentIDs: [String]
    public var eventIDs: [String]
    public var dueAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString, boardID: String, title: String, summary: String? = nil,
        kind: BoardCardKind = .manualTask, status: BoardCardStatus07A = .inbox,
        priority: BoardCardPriority = .normal, assignee: BoardAssignee? = nil,
        source: BoardCardSource = BoardCardSource(), links: [BoardLink] = [],
        artifactIDs: [String] = [], blockerIDs: [String] = [], commentIDs: [String] = [],
        eventIDs: [String] = [], dueAt: Date? = nil,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.boardID = boardID; self.title = title; self.summary = summary
        self.kind = kind; self.status = status; self.priority = priority; self.assignee = assignee
        self.source = source; self.links = links; self.artifactIDs = artifactIDs
        self.blockerIDs = blockerIDs; self.commentIDs = commentIDs; self.eventIDs = eventIDs
        self.dueAt = dueAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Comment
// ═══════════════════════════════════════════════════════════════════

public struct BoardComment: Codable, Sendable, Identifiable {
    public let id: String
    public let cardID: String
    public let author: BoardAssignee
    public let body: String
    public let createdAt: Date
    public init(id: String = UUID().uuidString, cardID: String, author: BoardAssignee, body: String, createdAt: Date = Date()) {
        self.id = id; self.cardID = cardID; self.author = author; self.body = body; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Artifact
// ═══════════════════════════════════════════════════════════════════

public struct BoardArtifact: Codable, Sendable, Identifiable {
    public let id: String
    public let cardID: String
    public let kind: BoardArtifactKind
    public let title: String
    public let uri: String
    public let preview: String?
    public let createdAt: Date
    public init(id: String = UUID().uuidString, cardID: String, kind: BoardArtifactKind, title: String, uri: String, preview: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.cardID = cardID; self.kind = kind; self.title = title; self.uri = uri; self.preview = preview; self.createdAt = createdAt
    }
}

public enum BoardArtifactKind: String, Codable, Sendable {
    case file, diff, log, report, workflowRun, approvalPreview, transactionPreview, screenshot, other
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Blocker
// ═══════════════════════════════════════════════════════════════════

public struct BoardBlocker: Codable, Sendable, Identifiable {
    public let id: String
    public let cardID: String
    public let reason: BoardBlockerReason
    public let message: String
    public let createdAt: Date
    public var resolvedAt: Date?
    public init(id: String = UUID().uuidString, cardID: String, reason: BoardBlockerReason, message: String, createdAt: Date = Date(), resolvedAt: Date? = nil) {
        self.id = id; self.cardID = cardID; self.reason = reason; self.message = message; self.createdAt = createdAt; self.resolvedAt = resolvedAt
    }
}

public enum BoardBlockerReason: String, Codable, Sendable {
    case awaitingApproval, permissionDenied, missingInput, failedTool
    case failedWorkflow, blockedByPolicy, humanDecisionRequired, externalDependency
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Link
// ═══════════════════════════════════════════════════════════════════

public struct BoardLink: Codable, Sendable, Identifiable {
    public let id: String
    public let fromCardID: String
    public let toCardID: String
    public let kind: BoardLinkKind
    public init(id: String = UUID().uuidString, fromCardID: String, toCardID: String, kind: BoardLinkKind) {
        self.id = id; self.fromCardID = fromCardID; self.toCardID = toCardID; self.kind = kind
    }
}

public enum BoardLinkKind: String, Codable, Sendable {
    case dependsOn, blocks, relatesTo, duplicates, parent, child
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Board event
// ═══════════════════════════════════════════════════════════════════

public struct BoardEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let cardID: String?
    public let boardID: String
    public let type: BoardEventType
    public let actor: BoardAssignee
    public let message: String
    public let metadata: [String: JSONValue]
    public let createdAt: Date
    public init(
        id: String = UUID().uuidString, cardID: String? = nil, boardID: String,
        type: BoardEventType, actor: BoardAssignee, message: String,
        metadata: [String: JSONValue] = [:], createdAt: Date = Date()
    ) {
        self.id = id; self.cardID = cardID; self.boardID = boardID; self.type = type
        self.actor = actor; self.message = message; self.metadata = metadata; self.createdAt = createdAt
    }
}

public enum BoardEventType: String, Codable, Sendable {
    case cardCreated, cardUpdated, cardMoved, cardAssigned, cardCompleted
    case cardBlocked, cardUnblocked, commentAdded, artifactAdded, linkAdded
    case workflowRunLinked, approvalLinked, triggerEventLinked, auditLinked
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Filter
// ═══════════════════════════════════════════════════════════════════

public struct BoardCardFilter: Codable, Sendable {
    public let status: BoardCardStatus07A?
    public let kind: BoardCardKind?
    public let priority: BoardCardPriority?
    public let assigneeID: String?
    public let sourceKind: BoardCardSourceKind?
    public let search: String?
    public init(status: BoardCardStatus07A? = nil, kind: BoardCardKind? = nil,
                priority: BoardCardPriority? = nil, assigneeID: String? = nil,
                sourceKind: BoardCardSourceKind? = nil, search: String? = nil) {
        self.status = status; self.kind = kind; self.priority = priority
        self.assigneeID = assigneeID; self.sourceKind = sourceKind; self.search = search
    }
}
