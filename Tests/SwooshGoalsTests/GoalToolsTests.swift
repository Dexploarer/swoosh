// Tests/SwooshGoalsTests/GoalToolsTests.swift — Goal tool surface tests
//
// Tests goal_set, goal_status, and goal_abandon tools with their
// SwooshTool conformance, permissions, and execution.

import Testing
import Foundation
@testable import SwooshGoals
@testable import SwooshTools

// MARK: - Test Context

/// Builds a real `ToolContext` for tool tests. `ToolContext` is a struct
/// (not a protocol), so tests construct a value directly rather than
/// subclassing a mock. `sessionID` is non-optional in the current API.
private func makeContext(sessionID: String = "test-session") -> ToolContext {
    ToolContext(sessionID: sessionID)
}

// MARK: - Goal Tool Dependencies Tests

@Suite("GoalToolDependencies")
struct GoalToolDependenciesTests {

    @Test("Dependencies initializes with store")
    func initializesWithStore() {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)

        #expect(deps.store is InMemoryGoalStore)
    }

    @Test("Dependencies is Sendable")
    func isSendable() {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)

        let _: any Sendable = deps
        #expect(Bool(true))
    }
}

// MARK: - Goal Set Tool Tests

@Suite("GoalSetTool")
struct GoalSetToolTests {

    @Test("Tool conforms to SwooshTool protocol")
    func conformsToProtocol() {
        let _: any SwooshTool.Type = GoalSetTool.self
        #expect(Bool(true))
    }

    @Test("Tool has correct metadata")
    func correctMetadata() {
        #expect(GoalSetTool.name.rawValue == "goal_set")
        #expect(GoalSetTool.displayName == "Set a goal")
        #expect(GoalSetTool.permission == .goalsWrite)
        #expect(GoalSetTool.risk == .low)
        #expect(GoalSetTool.approval == .never)
        #expect(GoalSetTool.toolset == .goals)
    }

    @Test("Input initializes with defaults")
    func inputWithDefaults() {
        let input = GoalSetInput(statement: "Test goal")

        #expect(input.statement == "Test goal")
        #expect(input.maxIterations == nil)
    }

    @Test("Input initializes with all values")
    func inputWithAllValues() {
        let input = GoalSetInput(statement: "Test", maxIterations: 15)

        #expect(input.statement == "Test")
        #expect(input.maxIterations == 15)
    }

    @Test("Output has correct fields")
    func outputFields() {
        let output = GoalSetOutput(id: "abc-123", statement: "Test goal", state: .pending)

        #expect(output.id == "abc-123")
        #expect(output.statement == "Test goal")
        #expect(output.state == .pending)
    }

    @Test("Tool creates goal with defaults")
    func createsGoalWithDefaults() async throws {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)
        let tool = GoalSetTool(dependencies: deps)
        let context = makeContext(sessionID: "session-1")

        let input = GoalSetInput(statement: "My new goal")
        let output = try await tool.call(input, context: context)

        #expect(output.statement == "My new goal")
        #expect(output.state == .pending)
        #expect(output.id != "")

        // Verify in store
        let saved = try await store.get(id: output.id)
        #expect(saved?.statement == "My new goal")
        #expect(saved?.parentSessionID == "session-1")
        #expect(saved?.maxIterations == 20) // Default
    }

    @Test("Tool creates goal with custom max iterations")
    func createsGoalWithCustomIterations() async throws {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)
        let tool = GoalSetTool(dependencies: deps)
        // ToolContext.sessionID is non-optional; the tool propagates it to
        // Goal.parentSessionID. Assert the propagated value rather than nil.
        let context = makeContext(sessionID: "session-2")

        let input = GoalSetInput(statement: "Custom", maxIterations: 10)
        let output = try await tool.call(input, context: context)

        let saved = try await store.get(id: output.id)
        #expect(saved?.maxIterations == 10)
        #expect(saved?.parentSessionID == "session-2")
    }

    @Test("Tool handles empty statement")
    func handlesEmptyStatement() async throws {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)
        let tool = GoalSetTool(dependencies: deps)
        let context = makeContext()

        let input = GoalSetInput(statement: "")
        let output = try await tool.call(input, context: context)

        #expect(output.statement == "")

        let saved = try await store.get(id: output.id)
        #expect(saved?.statement == "")
    }

    @Test("Tool handles long statement")
    func handlesLongStatement() async throws {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)
        let tool = GoalSetTool(dependencies: deps)
        let context = makeContext()

        let longStatement = String(repeating: "Objective ", count: 1000)
        let input = GoalSetInput(statement: longStatement)
        let output = try await tool.call(input, context: context)

        #expect(output.statement.count > 8000)
    }
}

// MARK: - Goal Status Tool Tests

@Suite("GoalStatusTool")
struct GoalStatusToolTests {

    @Test("Tool conforms to SwooshTool protocol")
    func conformsToProtocol() {
        let _: any SwooshTool.Type = GoalStatusTool.self
        #expect(Bool(true))
    }

    @Test("Tool has correct metadata")
    func correctMetadata() {
        #expect(GoalStatusTool.name.rawValue == "goal_status")
        #expect(GoalStatusTool.displayName == "Goal status")
        #expect(GoalStatusTool.permission == .goalsRead)
        #expect(GoalStatusTool.risk == .readOnly)
        #expect(GoalStatusTool.approval == .never)
        #expect(GoalStatusTool.toolset == .goals)
    }

    @Test("Input initializes with nil id")
    func inputWithNilId() {
        let input = GoalStatusInput()

        #expect(input.id == nil)
    }

    @Test("Input initializes with id")
    func inputWithId() {
        let input = GoalStatusInput(id: "goal-123")

        #expect(input.id == "goal-123")
    }

    @Test("Returns single goal when id provided")
    func returnsSingleGoal() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Specific goal")
        try await store.save(goal)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalStatusTool(dependencies: deps)
        let context = makeContext()

        let input = GoalStatusInput(id: goal.id)
        let output = try await tool.call(input, context: context)

        #expect(output.goals.count == 1)
        #expect(output.goals[0].id == goal.id)
    }

    @Test("Returns active goals when no id provided")
    func returnsActiveGoals() async throws {
        let store = InMemoryGoalStore()

        let pending = Goal(statement: "Pending", state: .pending)
        let active = Goal(statement: "Active", state: .active)
        let completed = Goal(statement: "Completed", state: .completed)

        try await store.save(pending)
        try await store.save(active)
        try await store.save(completed)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalStatusTool(dependencies: deps)
        let context = makeContext()

        let input = GoalStatusInput()
        let output = try await tool.call(input, context: context)

        #expect(output.goals.count == 2)
        #expect(output.goals.contains { $0.statement == "Pending" })
        #expect(output.goals.contains { $0.statement == "Active" })
        #expect(!output.goals.contains { $0.statement == "Completed" })
    }

    @Test("Returns empty when id not found")
    func returnsEmptyForMissingId() async throws {
        let store = InMemoryGoalStore()

        let deps = GoalToolDependencies(store: store)
        let tool = GoalStatusTool(dependencies: deps)
        let context = makeContext()

        let input = GoalStatusInput(id: "non-existent")
        let output = try await tool.call(input, context: context)

        #expect(output.goals.isEmpty)
    }

    @Test("Returns empty when no active goals")
    func returnsEmptyWhenNoneActive() async throws {
        let store = InMemoryGoalStore()

        let completed = Goal(statement: "Completed", state: .completed)
        let abandoned = Goal(statement: "Abandoned", state: .abandoned)

        try await store.save(completed)
        try await store.save(abandoned)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalStatusTool(dependencies: deps)
        let context = makeContext()

        let input = GoalStatusInput()
        let output = try await tool.call(input, context: context)

        #expect(output.goals.isEmpty)
    }

    @Test("Returns goals with iterations")
    func returnsGoalsWithIterations() async throws {
        let store = InMemoryGoalStore()

        var goal = Goal(statement: "With iterations", state: .active)
        goal.iterations = [
            GoalIteration(iteration: 1, observation: "Step 1", judgement: .progressing),
            GoalIteration(iteration: 2, observation: "Step 2", judgement: .progressing)
        ]
        try await store.save(goal)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalStatusTool(dependencies: deps)
        let context = makeContext()

        let input = GoalStatusInput(id: goal.id)
        let output = try await tool.call(input, context: context)

        #expect(output.goals[0].iterations.count == 2)
    }
}

// MARK: - Goal Abandon Tool Tests

@Suite("GoalAbandonTool")
struct GoalAbandonToolTests {

    @Test("Tool conforms to SwooshTool protocol")
    func conformsToProtocol() {
        let _: any SwooshTool.Type = GoalAbandonTool.self
        #expect(Bool(true))
    }

    @Test("Tool has correct metadata")
    func correctMetadata() {
        #expect(GoalAbandonTool.name.rawValue == "goal_abandon")
        #expect(GoalAbandonTool.displayName == "Abandon a goal")
        #expect(GoalAbandonTool.permission == .goalsWrite)
        #expect(GoalAbandonTool.risk == .low)
        #expect(GoalAbandonTool.approval == .humanOnly)
        #expect(GoalAbandonTool.toolset == .goals)
    }

    @Test("Input requires id")
    func inputRequiresId() {
        let input = GoalAbandonInput(id: "goal-123")

        #expect(input.id == "goal-123")
    }

    @Test("Output has correct fields")
    func outputFields() {
        let output = GoalAbandonOutput(id: "abc", state: .abandoned)

        #expect(output.id == "abc")
        #expect(output.state == .abandoned)
    }

    @Test("Tool abandons goal")
    func abandonsGoal() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "To abandon", state: .active)
        try await store.save(goal)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalAbandonTool(dependencies: deps)
        let context = makeContext()

        let input = GoalAbandonInput(id: goal.id)
        let output = try await tool.call(input, context: context)

        #expect(output.id == goal.id)
        #expect(output.state == .abandoned)

        let saved = try await store.get(id: goal.id)
        #expect(saved?.state == .abandoned)
    }

    @Test("Tool abandons pending goal")
    func abandonsPendingGoal() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Pending", state: .pending)
        try await store.save(goal)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalAbandonTool(dependencies: deps)
        let context = makeContext()

        let input = GoalAbandonInput(id: goal.id)
        let output = try await tool.call(input, context: context)

        #expect(output.state == .abandoned)
    }

    @Test("Tool throws for non-existent goal")
    func throwsForMissingGoal() async {
        let store = InMemoryGoalStore()

        let deps = GoalToolDependencies(store: store)
        let tool = GoalAbandonTool(dependencies: deps)
        let context = makeContext()

        let input = GoalAbandonInput(id: "non-existent")

        await #expect(throws: GoalToolError.self) {
            _ = try await tool.call(input, context: context)
        }
    }

    @Test("Abandoning already abandoned goal is safe")
    func abandoningAbandonedSafe() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Already abandoned", state: .abandoned)
        try await store.save(goal)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalAbandonTool(dependencies: deps)
        let context = makeContext()

        let input = GoalAbandonInput(id: goal.id)
        let output = try await tool.call(input, context: context)

        #expect(output.state == .abandoned)
    }

    @Test("Abandoning completed goal works")
    func abandoningCompletedWorks() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Completed", state: .completed)
        try await store.save(goal)

        let deps = GoalToolDependencies(store: store)
        let tool = GoalAbandonTool(dependencies: deps)
        let context = makeContext()

        let input = GoalAbandonInput(id: goal.id)
        let output = try await tool.call(input, context: context)

        #expect(output.state == .abandoned)

        let saved = try await store.get(id: goal.id)
        #expect(saved?.state == .abandoned)
    }
}

// MARK: - GoalToolError Tests

@Suite("GoalToolError")
struct GoalToolErrorTests {

    @Test("NotFound error contains goal ID")
    func notFoundContainsID() {
        let error = GoalToolError.notFound("goal-123")

        if case .notFound(let id) = error {
            #expect(id == "goal-123")
        } else {
            Issue.record("Wrong error type")
        }
    }

    @Test("Error provides localized description")
    func localizedDescription() {
        let error = GoalToolError.notFound("abc")

        #expect(error.errorDescription?.contains("abc") == true)
    }

    @Test("GoalToolError is Sendable and LocalizedError")
    func conformsToProtocols() {
        let _: any Sendable.Type = GoalToolError.self
        let _: any LocalizedError.Type = GoalToolError.self
        #expect(Bool(true))
    }
}

// MARK: - Goal Tools Integration Tests

@Suite("Goal Tools Integration")
struct GoalToolsIntegrationTests {

    @Test("Full goal lifecycle via tools")
    func fullLifecycleViaTools() async throws {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)
        let context = makeContext(sessionID: "integration-test")

        // Create goal
        let setTool = GoalSetTool(dependencies: deps)
        let setOutput = try await setTool.call(
            GoalSetInput(statement: "Integration test goal", maxIterations: 10),
            context: context
        )
        #expect(setOutput.statement == "Integration test goal")

        // Check status
        let statusTool = GoalStatusTool(dependencies: deps)
        let statusOutput = try await statusTool.call(GoalStatusInput(), context: context)
        #expect(statusOutput.goals.count == 1)

        // Abandon goal
        let abandonTool = GoalAbandonTool(dependencies: deps)
        let abandonOutput = try await abandonTool.call(
            GoalAbandonInput(id: setOutput.id),
            context: context
        )
        #expect(abandonOutput.state == .abandoned)

        // Verify status no longer shows active
        let finalStatus = try await statusTool.call(GoalStatusInput(), context: context)
        #expect(finalStatus.goals.isEmpty)
    }

    @Test("Multiple goals via tools")
    func multipleGoalsViaTools() async throws {
        let store = InMemoryGoalStore()
        let deps = GoalToolDependencies(store: store)
        let context = makeContext()

        let setTool = GoalSetTool(dependencies: deps)

        // Create multiple goals
        for i in 1...5 {
            _ = try await setTool.call(
                GoalSetInput(statement: "Goal \(i)"),
                context: context
            )
        }

        // Check all active
        let statusTool = GoalStatusTool(dependencies: deps)
        let status = try await statusTool.call(GoalStatusInput(), context: context)
        #expect(status.goals.count == 5)

        // Abandon 2
        let abandonTool = GoalAbandonTool(dependencies: deps)
        let toAbandon = Array(status.goals.prefix(2))
        for goal in toAbandon {
            _ = try await abandonTool.call(GoalAbandonInput(id: goal.id), context: context)
        }

        // Check 3 remain active
        let finalStatus = try await statusTool.call(GoalStatusInput(), context: context)
        #expect(finalStatus.goals.count == 3)
    }
}
