// SwooshBoard/Board.swift — Executable task graph
//
// Not just a Kanban. Each card is a typed executable plan.
// Replayable. Testable. Observable. Cancellable.

import Foundation
import SwooshTools

// MARK: - Artifact reference

public struct ArtifactRef: Codable, Sendable {
    public let id: String
    public let kind: String
    public let path: String?

    public init(id: String = UUID().uuidString, kind: String, path: String? = nil) {
        self.id = id
        self.kind = kind
        self.path = path
    }
}

// MARK: - Task types

public enum BoardTaskKind: String, Codable, Sendable {
    case human
    case agent
    case workflow
    case shell
    case mcp
    case review
    case approval
}

public enum BoardTaskStatus: String, Codable, Sendable {
    case backlog
    case ready
    case inProgress
    case blocked
    case waitingForApproval
    case done
    case failed
    case cancelled
}

// MARK: - Board task

public struct BoardTask: Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var objective: String
    public var kind: BoardTaskKind
    public var status: BoardTaskStatus
    public var ownerAgent: String?
    public var requiredTools: Set<String>
    public var requiredPermissions: Set<SwooshPermission>
    public var dependencies: [UUID]
    public var artifacts: [ArtifactRef]
    public var acceptanceTests: [String]
    public var budget: AgentBudget?
    public var modelRoute: ModelRoute?
    public var failureHistory: [TaskFailure]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        objective: String,
        kind: BoardTaskKind = .agent,
        status: BoardTaskStatus = .backlog,
        ownerAgent: String? = nil,
        requiredTools: Set<String> = [],
        requiredPermissions: Set<SwooshPermission> = [],
        dependencies: [UUID] = [],
        artifacts: [ArtifactRef] = [],
        acceptanceTests: [String] = [],
        budget: AgentBudget? = nil,
        modelRoute: ModelRoute? = nil,
        failureHistory: [TaskFailure] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.objective = objective
        self.kind = kind
        self.status = status
        self.ownerAgent = ownerAgent
        self.requiredTools = requiredTools
        self.requiredPermissions = requiredPermissions
        self.dependencies = dependencies
        self.artifacts = artifacts
        self.acceptanceTests = acceptanceTests
        self.budget = budget
        self.modelRoute = modelRoute
        self.failureHistory = failureHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TaskFailure: Codable, Sendable {
    public let timestamp: Date
    public let error: String
    public let failedAtStep: String?
    public let modelUsed: String?
}

// MARK: - Replay options

public struct ReplayOptions: Sendable {
    public enum ReplayMode: Sendable {
        case fromBeginning
        case fromBeforeFailingToolCall
        case withDifferentModel(ModelRoute)
        case withRestrictedPermissions(Set<SwooshPermission>)
        case localModelOnly
    }

    public let mode: ReplayMode
    public let taskID: UUID

    public init(mode: ReplayMode, taskID: UUID) {
        self.mode = mode
        self.taskID = taskID
    }
}

// MARK: - Board actor

public actor SwooshBoard {
    private var tasks: [UUID: BoardTask] = [:]

    public init() {}

    // ── CRUD ───────────────────────────────────────────────────────

    public func create(_ task: BoardTask) -> BoardTask {
        var t = task
        t.updatedAt = Date()
        tasks[t.id] = t
        return t
    }

    public func list(status: BoardTaskStatus? = nil) -> [BoardTask] {
        let all = Array(tasks.values).sorted { $0.createdAt > $1.createdAt }
        if let s = status { return all.filter { $0.status == s } }
        return all
    }

    public func show(_ id: UUID) -> BoardTask? {
        tasks[id]
    }

    public func update(_ id: UUID, _ mutation: (inout BoardTask) -> Void) {
        guard var task = tasks[id] else { return }
        mutation(&task)
        task.updatedAt = Date()
        tasks[id] = task
    }

    // ── Status transitions ─────────────────────────────────────────

    public func claim(_ id: UUID, by agent: String) {
        update(id) { $0.ownerAgent = agent; $0.status = .inProgress }
    }

    public func complete(_ id: UUID) {
        update(id) { $0.status = .done }
    }

    public func block(_ id: UUID, reason: String) {
        update(id) {
            $0.status = .blocked
            $0.failureHistory.append(TaskFailure(timestamp: Date(), error: reason, failedAtStep: nil, modelUsed: nil))
        }
    }

    public func fail(_ id: UUID, error: String, step: String? = nil, model: String? = nil) {
        update(id) {
            $0.status = .failed
            $0.failureHistory.append(TaskFailure(timestamp: Date(), error: error, failedAtStep: step, modelUsed: model))
        }
    }

    public func cancel(_ id: UUID) {
        update(id) { $0.status = .cancelled }
    }

    // ── Replay ─────────────────────────────────────────────────────

    public func prepareReplay(_ options: ReplayOptions) -> BoardTask? {
        guard var original = tasks[options.taskID] else { return nil }
        original.status = .ready
        original.ownerAgent = nil
        // Clear failure history for fresh attempt
        // The original failures are preserved in the original task
        return original
    }
}
