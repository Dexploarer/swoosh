// SwooshGoals/GoalRunner.swift — Iterate against a goal until done — 0.1A
//
// The loop is fully implemented; the *intelligent* bits (running an
// agent turn, judging progress) come in as closures so this module
// stays free of model-provider dependencies. The caller supplies:
//
//   • `agentTurn`  — async closure that takes a Goal and returns the
//     agent's observation for this round. In practice this wraps an
//     `AgentKernel.run` or `SwooshExecutor.run` call.
//   • `judge`      — async closure that takes a Goal and the latest
//     observation and returns a `GoalJudgement` + rationale.
//
// Default judge is a string-heuristic local diagnostic. It scans the
// observation for lowercase sentinels: `goal_done` / `goal complete` /
// `[done]` → completed; `goal_blocked` / `need user` / `[needs-user]` →
// needsUserInput; `goal_stuck` / `[stuck]` → stuck. Everything else maps
// to `.progressing`. The real judge — a model call that reads the goal
// statement plus the most recent observation and decides — wires in
// later once a provider is in the daemon.

import Foundation

public actor GoalRunner {
    public typealias AgentTurn = @Sendable (Goal) async throws -> String
    public typealias Judge = @Sendable (Goal, String) async throws -> (GoalJudgement, String?)

    private let store: any GoalStoring
    private let agentTurn: AgentTurn
    private let judge: Judge

    public init(
        store: any GoalStoring,
        agentTurn: @escaping AgentTurn,
        judge: @escaping Judge = GoalRunner.heuristicJudge
    ) {
        self.store = store
        self.agentTurn = agentTurn
        self.judge = judge
    }

    /// Run a goal to terminal state (completed / abandoned) or until the
    /// iteration ceiling is hit. Returns the final goal record.
    @discardableResult
    public func run(goalID: String) async throws -> Goal {
        guard var goal = try await store.get(id: goalID) else {
            throw GoalRunnerError.notFound(goalID)
        }
        if goal.isTerminal { return goal }

        // Mark active on first iteration.
        if goal.state == .pending {
            try await store.setState(goalID: goal.id, state: .active)
            goal.state = .active
        }

        while !goal.isTerminal,
              goal.iterations.count < goal.maxIterations {
            let nextIndex = goal.iterations.count + 1

            let observation: String
            do {
                observation = try await agentTurn(goal)
            } catch {
                let iter = GoalIteration(
                    iteration: nextIndex,
                    observation: "agent turn failed: \(error.localizedDescription)",
                    judgement: .stuck,
                    judgeRationale: "agentTurn threw"
                )
                try await store.appendIteration(goalID: goal.id, iteration: iter)
                try await store.setState(goalID: goal.id, state: .abandoned)
                return try await store.get(id: goal.id) ?? goal
            }

            let (verdict, rationale): (GoalJudgement, String?)
            do {
                (verdict, rationale) = try await judge(goal, observation)
            } catch {
                (verdict, rationale) = (.stuck, "judge threw: \(error.localizedDescription)")
            }

            let iter = GoalIteration(
                iteration: nextIndex,
                observation: observation,
                judgement: verdict,
                judgeRationale: rationale
            )
            try await store.appendIteration(goalID: goal.id, iteration: iter)

            var shouldStop = false
            switch verdict {
            case .completed:
                try await store.setState(goalID: goal.id, state: .completed)
                shouldStop = true
            case .needsUserInput:
                try await store.setState(goalID: goal.id, state: .paused)
                shouldStop = true
            case .stuck where nextIndex >= goal.maxIterations:
                try await store.setState(goalID: goal.id, state: .abandoned)
            case .stuck, .progressing:
                break
            }

            // Reload to pick up the state changes.
            guard let refreshed = try await store.get(id: goal.id) else { break }
            goal = refreshed

            // A conclusive verdict ends the run: `.completed` is terminal,
            // and `.needsUserInput` parks the goal as `.paused` awaiting the
            // user — neither should keep iterating.
            if shouldStop { break }
        }

        if goal.state == .active {
            // Ran out of iterations without converging — only an still-active
            // goal is abandoned here; a `.paused` goal stays paused.
            try await store.setState(goalID: goal.id, state: .abandoned)
        }
        return try await store.get(id: goal.id) ?? goal
    }

    // MARK: - Default judge

    /// Stub judge that scans the observation for sentinel markers. Good
    /// enough for unit tests and offline use; replaced with a model-backed
    /// judge once a provider is wired into the daemon.
    public static let heuristicJudge: Judge = { _, observation in
        let lower = observation.lowercased()
        if lower.contains("goal_done") || lower.contains("goal complete")
            || lower.contains("[done]") {
            return (.completed, "matched done sentinel")
        }
        if lower.contains("goal_blocked") || lower.contains("need user")
            || lower.contains("[needs-user]") {
            return (.needsUserInput, "matched user-input sentinel")
        }
        if lower.contains("goal_stuck") || lower.contains("[stuck]") {
            return (.stuck, "matched stuck sentinel")
        }
        return (.progressing, "no terminal sentinel found")
    }
}

public enum GoalRunnerError: Error, Sendable, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "goal not found: \(id)"
        }
    }
}
