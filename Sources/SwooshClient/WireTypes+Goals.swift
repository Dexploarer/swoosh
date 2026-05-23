// SwooshClient/WireTypes+Goals.swift — 0.4A Tier 1 Goals API wire types
//
// Wire format for `GET /api/goals`, `POST /api/goals`, the `PATCH` /
// `POST /api/goals/{id}/abandon` mutations, and the iteration detail
// projection. `GoalRecordSummary` itself lives in WireTypes+Records.swift
// because the dashboard records endpoint reuses it.

import Foundation

public struct GoalIterationSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let iteration: Int
    public let sessionID: String?
    public let observation: String
    public let judgement: String
    public let judgeRationale: String?
    public let createdAt: Date

    public init(
        id: String,
        iteration: Int,
        sessionID: String?,
        observation: String,
        judgement: String,
        judgeRationale: String?,
        createdAt: Date
    ) {
        self.id = id
        self.iteration = iteration
        self.sessionID = sessionID
        self.observation = observation
        self.judgement = judgement
        self.judgeRationale = judgeRationale
        self.createdAt = createdAt
    }
}

public struct GoalDetailResponse: Codable, Sendable, Equatable {
    public let goal: GoalRecordSummary
    public let maxIterations: Int
    public let parentSessionID: String?
    public let createdAt: Date
    public let iterations: [GoalIterationSummary]

    public init(
        goal: GoalRecordSummary,
        maxIterations: Int,
        parentSessionID: String?,
        createdAt: Date,
        iterations: [GoalIterationSummary]
    ) {
        self.goal = goal
        self.maxIterations = maxIterations
        self.parentSessionID = parentSessionID
        self.createdAt = createdAt
        self.iterations = iterations
    }
}

public struct GoalsResponse: Codable, Sendable, Equatable {
    public let goals: [GoalRecordSummary]

    public init(goals: [GoalRecordSummary]) {
        self.goals = goals
    }
}

public struct GoalSetRequest: Codable, Sendable, Equatable {
    public let statement: String
    public let maxIterations: Int?
    public let parentSessionID: String?

    public init(statement: String, maxIterations: Int? = nil, parentSessionID: String? = nil) {
        self.statement = statement
        self.maxIterations = maxIterations
        self.parentSessionID = parentSessionID
    }
}

public struct GoalUpdateRequest: Codable, Sendable, Equatable {
    public let state: String

    public init(state: String) {
        self.state = state
    }
}

public struct GoalMutationResponse: Codable, Sendable, Equatable {
    public let goal: GoalRecordSummary
    public let message: String

    public init(goal: GoalRecordSummary, message: String) {
        self.goal = goal
        self.message = message
    }
}
