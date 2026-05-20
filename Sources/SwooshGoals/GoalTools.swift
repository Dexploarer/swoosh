// SwooshGoals/GoalTools.swift — Tool surface for persistent goals
//
// Four tools — set, status, list, abandon. The actual judge-loop is
// driven by GoalRunner; these tools are the surface the model (or the
// user via CLI) uses to put goals into and out of the queue.

import Foundation
import SwooshTools

public struct GoalToolDependencies: Sendable {
    public let store: any GoalStoring

    public init(store: any GoalStoring) {
        self.store = store
    }
}

// MARK: - goal_set

public struct GoalSetInput: Codable, Sendable {
    public let statement: String
    public let maxIterations: Int?
    public init(statement: String, maxIterations: Int? = nil) {
        self.statement = statement
        self.maxIterations = maxIterations
    }
}

public struct GoalSetOutput: Codable, Sendable {
    public let id: String
    public let statement: String
    public let state: GoalState
}

public struct GoalSetTool: SwooshTool {
    public typealias Input = GoalSetInput
    public typealias Output = GoalSetOutput
    public static let name: ToolName = "goal_set"
    public static let displayName = "Set a goal"
    public static let description = "Create a standing objective the agent will work toward across turns."
    public static let permission: SwooshPermission = .goalsWrite
    public static let risk: ToolRisk = .low
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .goals

    private let deps: GoalToolDependencies
    public init(dependencies: GoalToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let goal = Goal(
            statement: input.statement,
            parentSessionID: context.sessionID,
            maxIterations: input.maxIterations ?? 20
        )
        try await deps.store.save(goal)
        return Output(id: goal.id, statement: goal.statement, state: goal.state)
    }
}

// MARK: - goal_status

public struct GoalStatusInput: Codable, Sendable {
    public let id: String?
    public init(id: String? = nil) { self.id = id }
}

public struct GoalStatusOutput: Codable, Sendable {
    public let goals: [Goal]
}

public struct GoalStatusTool: SwooshTool {
    public typealias Input = GoalStatusInput
    public typealias Output = GoalStatusOutput
    public static let name: ToolName = "goal_status"
    public static let displayName = "Goal status"
    public static let description = "Return one goal (when id is supplied) or all active goals."
    public static let permission: SwooshPermission = .goalsRead
    public static let risk: ToolRisk = .readOnly
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .goals

    private let deps: GoalToolDependencies
    public init(dependencies: GoalToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        if let id = input.id, let one = try await deps.store.get(id: id) {
            return Output(goals: [one])
        }
        return Output(goals: try await deps.store.listActive())
    }
}

// MARK: - goal_abandon

public struct GoalAbandonInput: Codable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

public struct GoalAbandonOutput: Codable, Sendable {
    public let id: String
    public let state: GoalState
}

public struct GoalAbandonTool: SwooshTool {
    public typealias Input = GoalAbandonInput
    public typealias Output = GoalAbandonOutput
    public static let name: ToolName = "goal_abandon"
    public static let displayName = "Abandon a goal"
    public static let description = "Mark a goal abandoned. Stops the runner from advancing it."
    public static let permission: SwooshPermission = .goalsWrite
    public static let risk: ToolRisk = .low
    /// Abandoning a goal is a load-bearing decision; we ask the user
    /// rather than letting the model auto-decide.
    public static let approval: ApprovalPolicy = .humanOnly
    public static let toolset: ToolsetID = .goals

    private let deps: GoalToolDependencies
    public init(dependencies: GoalToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await deps.store.setState(goalID: input.id, state: .abandoned)
        guard let updated = try await deps.store.get(id: input.id) else {
            throw GoalToolError.notFound(input.id)
        }
        return Output(id: updated.id, state: updated.state)
    }
}

public enum GoalToolError: Error, Sendable, LocalizedError {
    case notFound(String)
    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "goal not found: \(id)"
        }
    }
}
