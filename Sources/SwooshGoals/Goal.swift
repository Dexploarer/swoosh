// SwooshGoals/Goal.swift — Persistent objectives, judge-evaluated — 0.1A
//
// Hermes-style /goal command. A Goal is a standing objective that
// survives across chat turns. After each turn that runs against an
// active goal, a judge model decides whether the goal is met, needs
// more work, or is stuck.
//
// The schema is intentionally cross-platform (no Foundation.Process,
// no AppKit) so the iPhone sees the same goal queue as the Mac.

import Foundation

/// Lifecycle state for a goal.
public enum GoalState: String, Codable, Sendable, CaseIterable {
    /// Created but not yet started.
    case pending
    /// Currently being worked on across one or more sessions.
    case active
    /// User paused; runner will not advance until reactivated.
    case paused
    /// Judge says the goal is met.
    case completed
    /// User gave up, or the runner hit its iteration ceiling.
    case abandoned
}

/// Judge verdict after an iteration.
public enum GoalJudgement: String, Codable, Sendable {
    case progressing
    case stuck
    case completed
    case needsUserInput
}

/// One pass against a goal — what the agent did, what the judge said.
public struct GoalIteration: Codable, Sendable, Identifiable {
    public let id: String
    public let iteration: Int            // 1-indexed; matches "(N/max)" in the UI
    public let sessionID: String?        // Chat session that produced this iteration
    public let observation: String       // Summary of the agent's action this round
    public let judgement: GoalJudgement
    public let judgeRationale: String?   // Why the judge said what it said
    public let createdAt: Date

    public init(
        iteration: Int,
        sessionID: String? = nil,
        observation: String,
        judgement: GoalJudgement,
        judgeRationale: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID().uuidString
        self.iteration = iteration
        self.sessionID = sessionID
        self.observation = observation
        self.judgement = judgement
        self.judgeRationale = judgeRationale
        self.createdAt = createdAt
    }
}

/// A standing objective the agent works toward across conversation turns.
public struct Goal: Codable, Sendable, Identifiable {
    public let id: String
    public var statement: String           // "Ship the iOS app to TestFlight"
    public var state: GoalState
    public var parentSessionID: String?    // Session that created the goal
    public var maxIterations: Int          // Hard ceiling — matches Hermes's 20
    public var iterations: [GoalIteration]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        statement: String,
        parentSessionID: String? = nil,
        maxIterations: Int = 20,
        state: GoalState = .pending
    ) {
        self.id = UUID().uuidString
        self.statement = statement
        self.state = state
        self.parentSessionID = parentSessionID
        self.maxIterations = maxIterations
        self.iterations = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Latest judge verdict — `nil` if the goal hasn't run yet.
    public var lastJudgement: GoalJudgement? { iterations.last?.judgement }

    /// `(N, max)` progress tuple, with N being iterations completed.
    public var progress: (completed: Int, ceiling: Int) {
        (iterations.count, maxIterations)
    }

    /// True when no further iterations should run automatically.
    public var isTerminal: Bool {
        switch state {
        case .completed, .abandoned: return true
        case .pending, .active, .paused: return false
        }
    }
}
