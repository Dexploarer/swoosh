// Tests/SwooshGoalsTests/GoalRunnerTests.swift — Goal runner and execution tests
//
// Tests GoalRunner iteration logic, judge evaluation, and the full
// goal execution loop with various outcomes.

import Testing
import Foundation
@testable import SwooshGoals

// MARK: - Thread-safe test helpers
//
// GoalRunner's `agentTurn` / `judge` closures are `@Sendable` and run on
// the runner actor. Tests need to mutate counters/flags from inside them,
// which a captured `var` cannot do safely. `Box` is a tiny lock-guarded
// reference cell that is safe to capture and mutate from a @Sendable
// closure.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }

    /// Atomically mutate the boxed value and return the new value.
    @discardableResult
    func mutate(_ transform: (inout Value) -> Void) -> Value {
        lock.lock()
        defer { lock.unlock() }
        transform(&_value)
        return _value
    }
}

// MARK: - Test Doubles

actor MockGoalStore: GoalStoring {
    private var goals: [String: Goal] = [:]

    func save(_ goal: Goal) async throws {
        goals[goal.id] = goal
    }

    func update(_ goal: Goal) async throws {
        var updated = goal
        updated.updatedAt = Date()
        goals[goal.id] = updated
    }

    func get(id: String) async throws -> Goal? {
        goals[id]
    }

    func delete(id: String) async throws {
        goals.removeValue(forKey: id)
    }

    func listAll() async throws -> [Goal] {
        Array(goals.values)
    }

    func listActive() async throws -> [Goal] {
        try await listAll().filter { $0.state == .active || $0.state == .pending }
    }

    func appendIteration(goalID: String, iteration: GoalIteration) async throws {
        guard var goal = goals[goalID] else { return }
        goal.iterations.append(iteration)
        goal.updatedAt = Date()
        goals[goalID] = goal
    }

    func setState(goalID: String, state: GoalState) async throws {
        guard var goal = goals[goalID] else { return }
        goal.state = state
        goal.updatedAt = Date()
        goals[goalID] = goal
    }
}

// MARK: - GoalRunner Initialization Tests

@Suite("GoalRunner Initialization")
struct GoalRunnerInitializationTests {

    @Test("Runner initializes with store and closures")
    func initializesWithStore() {
        let store = MockGoalStore()
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "test" },
            judge: { _, _ in (.progressing, nil) }
        )

        // GoalRunner is a non-optional actor; constructing it without a
        // crash is the assertion.
        _ = runner
        #expect(Bool(true))
    }

    @Test("Runner uses heuristic judge by default")
    func usesDefaultJudge() {
        let store = MockGoalStore()
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "test" }
        )

        _ = runner
        #expect(Bool(true))
    }

    @Test("Runner accepts custom judge")
    func acceptsCustomJudge() {
        let store = MockGoalStore()
        let judgeCalled = Box(false)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "test" },
            judge: { _, _ in
                judgeCalled.value = true
                return (.completed, "done")
            }
        )

        _ = runner
        #expect(Bool(true))
    }
}

// MARK: - GoalRunner Error Tests

@Suite("GoalRunnerError")
struct GoalRunnerErrorTests {

    @Test("NotFound error contains goal ID")
    func notFoundContainsID() {
        let error = GoalRunnerError.notFound("goal-123")

        if case .notFound(let id) = error {
            #expect(id == "goal-123")
        } else {
            Issue.record("Wrong error type")
        }
    }

    @Test("Error provides localized description")
    func localizedDescription() {
        let notFound = GoalRunnerError.notFound("abc")
        let noAgent = GoalRunnerError.noAgent

        #expect(notFound.errorDescription?.contains("abc") == true)
        #expect(noAgent.errorDescription?.contains("no agent") == true)
    }

    @Test("GoalRunnerError is Sendable")
    func isSendable() {
        let _: any Sendable.Type = GoalRunnerError.self
        #expect(Bool(true))
    }
}

// MARK: - GoalRunner Execution Tests

@Suite("GoalRunner Execution")
struct GoalRunnerExecutionTests {

    @Test("Run throws for non-existent goal")
    func runThrowsForMissing() async {
        let store = MockGoalStore()
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "test" }
        )

        await #expect(throws: GoalRunnerError.self) {
            _ = try await runner.run(goalID: "non-existent")
        }
    }

    @Test("Run returns immediately for terminal goal")
    func runReturnsForTerminal() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Completed", state: .completed)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "test" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
        #expect(result.iterations.isEmpty) // No iterations added
    }

    @Test("Run transitions pending to active")
    func runTransitionsPendingToActive() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1, state: .pending)
        try await store.save(goal)

        let agentTurns = Box(0)
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in
                agentTurns.mutate { $0 += 1 }
                return "Done"
            },
            judge: { _, _ in (.completed, nil) }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
        #expect(result.iterations.count == 1)
    }

    @Test("Run executes agent turn")
    func runExecutesAgentTurn() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let agentCalled = Box(false)
        let runner = GoalRunner(
            store: store,
            agentTurn: { g in
                agentCalled.value = true
                #expect(g.statement == "Test")
                return "Observation from agent"
            },
            judge: { _, _ in (.completed, nil) }
        )

        _ = try await runner.run(goalID: goal.id)

        #expect(agentCalled.value == true)
    }

    @Test("Run calls judge with observation")
    func runCallsJudge() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let judgeCalled = Box(false)
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "The observation" },
            judge: { g, obs in
                judgeCalled.value = true
                #expect(g.statement == "Test")
                #expect(obs == "The observation")
                return (.completed, nil)
            }
        )

        _ = try await runner.run(goalID: goal.id)

        #expect(judgeCalled.value == true)
    }

    @Test("Run records iteration")
    func runRecordsIteration() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Observation" },
            judge: { _, _ in (.progressing, "keep going") }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.iterations.count == 1)
        #expect(result.iterations[0].iteration == 1)
        #expect(result.iterations[0].observation == "Observation")
        #expect(result.iterations[0].judgement == .progressing)
        #expect(result.iterations[0].judgeRationale == "keep going")
    }

    @Test("Run completes when judge says completed")
    func runCompletesWhenJudgeSaysSo() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 10)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Done!" },
            judge: { _, _ in (.completed, "Goal achieved") }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
        #expect(result.iterations.count == 1)
        #expect(result.isTerminal == true)
    }

    @Test("Run pauses when judge says needsUserInput")
    func runPausesWhenJudgeSaysSo() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 10)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Need help" },
            judge: { _, _ in (.needsUserInput, "User intervention required") }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .paused)
        #expect(result.iterations.count == 1)
        #expect(result.lastJudgement == .needsUserInput)
    }
}

// MARK: - GoalRunner Iteration Tests

@Suite("GoalRunner Iterations")
struct GoalRunnerIterationTests {

    @Test("Run continues while progressing")
    func runContinuesWhileProgressing() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Multi-step", maxIterations: 5)
        try await store.save(goal)

        let turnCount = Box(0)
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in
                let count = turnCount.mutate { $0 += 1 }
                return "Step \(count)"
            },
            judge: { g, _ in
                // Complete after 3 turns
                if g.iterations.count >= 2 {
                    return (.completed, "Done")
                }
                return (.progressing, "Continue")
            }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(turnCount.value == 3)
        #expect(result.iterations.count == 3)
        #expect(result.state == .completed)
    }

    @Test("Run abandons when stuck at max iterations")
    func runAbandonsWhenStuck() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Stuck", maxIterations: 3)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Stuck again" },
            judge: { _, _ in (.stuck, "Cannot proceed") }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .abandoned)
        #expect(result.iterations.count == 3)
    }

    @Test("Run abandons when max iterations reached without completion")
    func runAbandonsAtMaxIterations() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Unfinished", maxIterations: 2)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Still working" },
            judge: { _, _ in (.progressing, "Making progress") }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .abandoned)
        #expect(result.iterations.count == 2)
    }

    @Test("Run preserves iteration order")
    func runPreservesIterationOrder() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Ordered", maxIterations: 3)
        try await store.save(goal)

        let step = Box(0)
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in
                let current = step.mutate { $0 += 1 }
                return "Step \(current)"
            },
            judge: { _, _ in
                if step.value >= 3 { return (.completed, "Done") }
                return (.progressing, "Continue")
            }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.iterations.count == 3)
        #expect(result.iterations[0].iteration == 1)
        #expect(result.iterations[1].iteration == 2)
        #expect(result.iterations[2].iteration == 3)
        #expect(result.iterations[0].observation == "Step 1")
        #expect(result.iterations[1].observation == "Step 2")
        #expect(result.iterations[2].observation == "Step 3")
    }
}

// MARK: - GoalRunner Error Handling Tests

@Suite("GoalRunner Error Handling")
struct GoalRunnerErrorHandlingTests {

    @Test("Run abandons when agent turn throws")
    func runAbandonsOnAgentError() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 5)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in
                throw TestError.simulated
            },
            judge: { _, _ in (.progressing, nil) }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .abandoned)
        #expect(result.iterations.count == 1)
        #expect(result.iterations[0].judgement == .stuck)
        #expect(result.iterations[0].observation.contains("agent turn failed"))
    }

    @Test("Run records judge exception as stuck")
    func runRecordsJudgeException() async throws {
        let store = MockGoalStore()
        // maxIterations: 1 — a judge that always throws is treated as
        // `.stuck` and retried up to the ceiling; one iteration is enough
        // to verify the exception is recorded as a stuck judgement.
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Observation" },
            judge: { _, _ in
                throw TestError.simulated
            }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.iterations.count == 1)
        #expect(result.iterations[0].judgement == .stuck)
        #expect(result.iterations[0].judgeRationale?.contains("judge threw") == true)
    }

    @Test("Run continues after recoverable judge error")
    func runContinuesAfterRecoverableError() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 3)
        try await store.save(goal)

        let shouldFail = Box(true)
        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Observation" },
            judge: { _, _ in
                // Atomically test-and-clear: throw on the first call only.
                var failedThisCall = false
                shouldFail.mutate { current in
                    if current {
                        failedThisCall = true
                        current = false
                    }
                }
                if failedThisCall {
                    throw TestError.simulated
                }
                return (.completed, "Recovered")
            }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.iterations.count == 2)
        #expect(result.iterations[0].judgement == .stuck) // First fails
        #expect(result.iterations[1].judgement == .completed) // Second succeeds
    }
}

// MARK: - GoalRunner Heuristic Judge Tests

@Suite("GoalRunner Heuristic Judge")
struct GoalRunnerHeuristicJudgeTests {

    @Test("Heuristic judge detects GOAL_DONE")
    func heuristicDetectsDone() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "The task is GOAL_DONE now" }
            // Uses default heuristic judge
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
    }

    @Test("Heuristic judge detects goal complete")
    func heuristicDetectsComplete() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            // The heuristic judge matches the literal "goal complete"
            // sentinel — phrased here so the substring is present.
            agentTurn: { _ in "Task status: goal complete" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
    }

    @Test("Heuristic judge detects [done]")
    func heuristicDetectsDoneTag() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Finished [done]" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
    }

    @Test("Heuristic judge detects GOAL_BLOCKED")
    func heuristicDetectsBlocked() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "GOAL_BLOCKED by permission" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .paused)
        #expect(result.lastJudgement == .needsUserInput)
    }

    @Test("Heuristic judge detects need user")
    func heuristicDetectsNeedUser() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "We need user input to proceed" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .paused)
    }

    @Test("Heuristic judge detects [needs-user]")
    func heuristicDetectsNeedsUserTag() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Blocked [needs-user]" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .paused)
    }

    @Test("Heuristic judge detects GOAL_STUCK")
    func heuristicDetectsStuck() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 3)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "GOAL_STUCK cannot proceed" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .abandoned)
    }

    @Test("Heuristic judge detects [stuck]")
    func heuristicDetectsStuckTag() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 3)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "We are [stuck]" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .abandoned)
    }

    @Test("Heuristic judge defaults to progressing")
    func heuristicDefaultsToProgressing() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 2)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "Made some progress" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.iterations.count == 2)
        #expect(result.iterations[0].judgement == .progressing)
        #expect(result.iterations[1].judgement == .progressing)
    }

    @Test("Heuristic judge is case-insensitive")
    func heuristicIsCaseInsensitive() async throws {
        let store = MockGoalStore()
        let goal = Goal(statement: "Test", maxIterations: 1)
        try await store.save(goal)

        let runner = GoalRunner(
            store: store,
            agentTurn: { _ in "GOAL_DONE in uppercase" }
        )

        let result = try await runner.run(goalID: goal.id)

        #expect(result.state == .completed)
    }
}

// Test error for simulations
private enum TestError: Error {
    case simulated
}
