// SwooshDaemon/GoalsAPIBridge.swift — Goal store ↔ HTTP API
//
// Maps the `GoalStoring` actor surface into the wire types the API
// serves. Kept out of Daemon.swift so the long startup function stays
// readable. Follows the same pattern as PluginAPIBridge.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshGoals

extension SwooshDaemon {
    static func goalSummary(_ goal: Goal) -> GoalRecordSummary {
        GoalRecordSummary(
            id: goal.id,
            statement: goal.statement,
            state: goal.state.rawValue,
            progress: "\(goal.progress.completed)/\(goal.progress.ceiling)",
            updatedAt: goal.updatedAt
        )
    }

    static func goalIterationSummary(_ iteration: GoalIteration) -> GoalIterationSummary {
        GoalIterationSummary(
            id: iteration.id,
            iteration: iteration.iteration,
            sessionID: iteration.sessionID,
            observation: iteration.observation,
            judgement: iteration.judgement.rawValue,
            judgeRationale: iteration.judgeRationale,
            createdAt: iteration.createdAt
        )
    }

    static func goalDetailResponse(_ goal: Goal) -> GoalDetailResponse {
        GoalDetailResponse(
            goal: goalSummary(goal),
            maxIterations: goal.maxIterations,
            parentSessionID: goal.parentSessionID,
            createdAt: goal.createdAt,
            iterations: goal.iterations.map(goalIterationSummary)
        )
    }

    static func goalsResponse(store: any GoalStoring) async -> GoalsResponse {
        let goals = (try? await store.listAll()) ?? []
        let sorted = goals.sorted { $0.updatedAt > $1.updatedAt }
        return GoalsResponse(goals: sorted.map(goalSummary))
    }

    static func goalDetailResponse(
        store: any GoalStoring, id: String
    ) async throws -> GoalDetailResponse {
        guard let goal = try await store.get(id: id) else {
            throw APIError.notFound("goal not found: \(id)")
        }
        return goalDetailResponse(goal)
    }

    static func setGoalResponse(
        store: any GoalStoring, request: GoalSetRequest
    ) async throws -> GoalMutationResponse {
        let trimmed = request.statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.badRequest("goal statement is empty")
        }
        var goal = Goal(
            statement: trimmed,
            parentSessionID: request.parentSessionID,
            maxIterations: request.maxIterations ?? 20,
            state: .pending
        )
        goal.state = .pending
        try await store.save(goal)
        return GoalMutationResponse(
            goal: goalSummary(goal),
            message: "Goal created."
        )
    }

    static func abandonGoalResponse(
        store: any GoalStoring, id: String
    ) async throws -> GoalMutationResponse {
        guard var goal = try await store.get(id: id) else {
            throw APIError.notFound("goal not found: \(id)")
        }
        try await store.setState(goalID: id, state: .abandoned)
        goal.state = .abandoned
        goal.updatedAt = Date()
        return GoalMutationResponse(
            goal: goalSummary(goal),
            message: "Goal abandoned."
        )
    }

    static func updateGoalResponse(
        store: any GoalStoring, id: String, request: GoalUpdateRequest
    ) async throws -> GoalMutationResponse {
        guard let newState = GoalState(rawValue: request.state) else {
            throw APIError.badRequest("unknown goal state: \(request.state)")
        }
        guard var goal = try await store.get(id: id) else {
            throw APIError.notFound("goal not found: \(id)")
        }
        try await store.setState(goalID: id, state: newState)
        goal.state = newState
        goal.updatedAt = Date()
        return GoalMutationResponse(
            goal: goalSummary(goal),
            message: "Goal state set to \(newState.rawValue)."
        )
    }
}
