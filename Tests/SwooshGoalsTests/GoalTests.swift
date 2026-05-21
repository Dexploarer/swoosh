// Tests/SwooshGoalsTests/GoalTests.swift — Goal model and lifecycle tests
//
// Tests the Goal model, GoalState transitions, GoalIteration, and
// the core goal data structures.

import Testing
import Foundation
@testable import SwooshGoals

// MARK: - GoalState Tests

@Suite("GoalState")
struct GoalStateTests {

    @Test("All GoalState cases exist")
    func allCasesExist() {
        let states: [GoalState] = [.pending, .active, .paused, .completed, .abandoned]
        #expect(states.count == 5)
    }

    @Test("GoalState is Codable and Sendable")
    func isCodableAndSendable() {
        let state: GoalState = .active

        // Codable
        let data = try? JSONEncoder().encode(state)
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(GoalState.self, from: data!)
        #expect(decoded == .active)

        // Sendable (compile-time check)
        let _: any Sendable.Type = GoalState.self
    }

    @Test("GoalState raw values are correct")
    func rawValuesCorrect() {
        #expect(GoalState.pending.rawValue == "pending")
        #expect(GoalState.active.rawValue == "active")
        #expect(GoalState.paused.rawValue == "paused")
        #expect(GoalState.completed.rawValue == "completed")
        #expect(GoalState.abandoned.rawValue == "abandoned")
    }

    @Test("GoalState CaseIterable works")
    func caseIterableWorks() {
        let allCases = GoalState.allCases
        #expect(allCases.count == 5)
        #expect(allCases.contains(.pending))
        #expect(allCases.contains(.active))
        #expect(allCases.contains(.paused))
        #expect(allCases.contains(.completed))
        #expect(allCases.contains(.abandoned))
    }
}

// MARK: - GoalJudgement Tests

@Suite("GoalJudgement")
struct GoalJudgementTests {

    @Test("All GoalJudgement cases exist")
    func allCasesExist() {
        let judgements: [GoalJudgement] = [.progressing, .stuck, .completed, .needsUserInput]
        #expect(judgements.count == 4)
    }

    @Test("GoalJudgement is Codable and Sendable")
    func isCodableAndSendable() {
        let judgement: GoalJudgement = .completed

        let data = try? JSONEncoder().encode(judgement)
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(GoalJudgement.self, from: data!)
        #expect(decoded == .completed)
    }

    @Test("GoalJudgement raw values are correct")
    func rawValuesCorrect() {
        #expect(GoalJudgement.progressing.rawValue == "progressing")
        #expect(GoalJudgement.stuck.rawValue == "stuck")
        #expect(GoalJudgement.completed.rawValue == "completed")
        #expect(GoalJudgement.needsUserInput.rawValue == "needsUserInput")
    }
}

// MARK: - GoalIteration Tests

@Suite("GoalIteration")
struct GoalIterationTests {

    @Test("GoalIteration initializes with defaults")
    func initializesWithDefaults() {
        let iteration = GoalIteration(
            iteration: 1,
            observation: "Started working on goal",
            judgement: .progressing
        )

        #expect(iteration.iteration == 1)
        #expect(iteration.observation == "Started working on goal")
        #expect(iteration.judgement == .progressing)
        #expect(iteration.sessionID == nil)
        #expect(iteration.judgeRationale == nil)
        #expect(iteration.id != "")
        #expect(iteration.createdAt <= Date())
    }

    @Test("GoalIteration initializes with all values")
    func initializesWithAllValues() {
        let date = Date(timeIntervalSince1970: 1000)
        let iteration = GoalIteration(
            iteration: 3,
            sessionID: "session-123",
            observation: "Made progress",
            judgement: .progressing,
            judgeRationale: "Good progress made",
            createdAt: date
        )

        #expect(iteration.iteration == 3)
        #expect(iteration.sessionID == "session-123")
        #expect(iteration.observation == "Made progress")
        #expect(iteration.judgement == .progressing)
        #expect(iteration.judgeRationale == "Good progress made")
        #expect(iteration.createdAt == date)
    }

    @Test("GoalIteration is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let iteration = GoalIteration(iteration: 1, observation: "test", judgement: .completed)

        // Identifiable
        _ = iteration.id

        // Codable
        let data = try? JSONEncoder().encode(iteration)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = GoalIteration.self
    }

    @Test("GoalIteration encodes and decodes correctly")
    func roundTrip() throws {
        let original = GoalIteration(
            iteration: 5,
            sessionID: "abc-123",
            observation: "Test observation",
            judgement: .stuck,
            judgeRationale: "Blocked by dependency"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GoalIteration.self, from: data)

        #expect(decoded.iteration == original.iteration)
        #expect(decoded.sessionID == original.sessionID)
        #expect(decoded.observation == original.observation)
        #expect(decoded.judgement == original.judgement)
        #expect(decoded.judgeRationale == original.judgeRationale)
        #expect(decoded.id == original.id)
    }

    @Test("GoalIteration handles long observations")
    func handlesLongObservations() {
        let longObservation = String(repeating: "Observation text. ", count: 1000)
        let iteration = GoalIteration(
            iteration: 1,
            observation: longObservation,
            judgement: .progressing
        )

        #expect(iteration.observation.count > 10000)
    }
}

// MARK: - Goal Tests

@Suite("Goal Initialization")
struct GoalInitializationTests {

    @Test("Goal initializes with defaults")
    func initializesWithDefaults() {
        let goal = Goal(statement: "Ship the iOS app")

        #expect(goal.statement == "Ship the iOS app")
        #expect(goal.state == .pending)
        #expect(goal.parentSessionID == nil)
        #expect(goal.maxIterations == 20)
        #expect(goal.iterations.isEmpty)
        #expect(goal.id != "")
        #expect(goal.createdAt <= Date())
        #expect(goal.updatedAt <= Date())
    }

    @Test("Goal initializes with custom values")
    func initializesWithCustomValues() {
        let goal = Goal(
            statement: "Write documentation",
            parentSessionID: "session-456",
            maxIterations: 10,
            state: .active
        )

        #expect(goal.statement == "Write documentation")
        #expect(goal.parentSessionID == "session-456")
        #expect(goal.maxIterations == 10)
        #expect(goal.state == .active)
    }

    @Test("Goal is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let goal = Goal(statement: "Test goal")

        // Identifiable
        _ = goal.id

        // Codable
        let data = try? JSONEncoder().encode(goal)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = Goal.self
    }

    @Test("Goal round-trip encoding")
    func roundTrip() throws {
        let original = Goal(
            statement: "Round trip test",
            parentSessionID: "session-789",
            maxIterations: 15,
            state: .active
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Goal.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.statement == original.statement)
        #expect(decoded.parentSessionID == original.parentSessionID)
        #expect(decoded.maxIterations == original.maxIterations)
        #expect(decoded.state == original.state)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.updatedAt == original.updatedAt)
    }
}

@Suite("Goal Computed Properties")
struct GoalComputedPropertyTests {

    @Test("lastJudgement returns nil for new goal")
    func lastJudgementNilForNew() {
        let goal = Goal(statement: "New goal")
        #expect(goal.lastJudgement == nil)
    }

    @Test("lastJudgement returns last iteration's judgement")
    func lastJudgementReturnsLast() {
        var goal = Goal(statement: "Test goal")
        goal.iterations = [
            GoalIteration(iteration: 1, observation: "First", judgement: .progressing),
            GoalIteration(iteration: 2, observation: "Second", judgement: .completed)
        ]

        #expect(goal.lastJudgement == .completed)
    }

    @Test("progress returns zero for new goal")
    func progressZeroForNew() {
        let goal = Goal(statement: "New goal")
        let (completed, ceiling) = goal.progress

        #expect(completed == 0)
        #expect(ceiling == 20)
    }

    @Test("progress returns correct counts")
    func progressReturnsCounts() {
        var goal = Goal(statement: "Test", maxIterations: 15)
        goal.iterations = [
            GoalIteration(iteration: 1, observation: "First", judgement: .progressing),
            GoalIteration(iteration: 2, observation: "Second", judgement: .progressing)
        ]

        let (completed, ceiling) = goal.progress

        #expect(completed == 2)
        #expect(ceiling == 15)
    }

    @Test("isTerminal returns false for pending goal")
    func isTerminalFalseForPending() {
        let goal = Goal(statement: "Pending", state: .pending)
        #expect(goal.isTerminal == false)
    }

    @Test("isTerminal returns false for active goal")
    func isTerminalFalseForActive() {
        let goal = Goal(statement: "Active", state: .active)
        #expect(goal.isTerminal == false)
    }

    @Test("isTerminal returns false for paused goal")
    func isTerminalFalseForPaused() {
        let goal = Goal(statement: "Paused", state: .paused)
        #expect(goal.isTerminal == false)
    }

    @Test("isTerminal returns true for completed goal")
    func isTerminalTrueForCompleted() {
        let goal = Goal(statement: "Completed", state: .completed)
        #expect(goal.isTerminal == true)
    }

    @Test("isTerminal returns true for abandoned goal")
    func isTerminalTrueForAbandoned() {
        let goal = Goal(statement: "Abandoned", state: .abandoned)
        #expect(goal.isTerminal == true)
    }
}

@Suite("Goal State Transitions")
struct GoalStateTransitionTests {

    @Test("Goal transitions from pending to active")
    func pendingToActive() {
        var goal = Goal(statement: "Test", state: .pending)
        goal.state = .active
        #expect(goal.state == .active)
    }

    @Test("Goal transitions from active to paused")
    func activeToPaused() {
        var goal = Goal(statement: "Test", state: .active)
        goal.state = .paused
        #expect(goal.state == .paused)
    }

    @Test("Goal transitions from active to completed")
    func activeToCompleted() {
        var goal = Goal(statement: "Test", state: .active)
        goal.state = .completed
        #expect(goal.state == .completed)
        #expect(goal.isTerminal == true)
    }

    @Test("Goal transitions from active to abandoned")
    func activeToAbandoned() {
        var goal = Goal(statement: "Test", state: .active)
        goal.state = .abandoned
        #expect(goal.state == .abandoned)
        #expect(goal.isTerminal == true)
    }

    @Test("Goal can transition from paused to active")
    func pausedToActive() {
        var goal = Goal(statement: "Test", state: .paused)
        goal.state = .active
        #expect(goal.state == .active)
    }
}

@Suite("Goal Edge Cases")
struct GoalEdgeCaseTests {

    @Test("Goal handles empty statement")
    func handlesEmptyStatement() {
        let goal = Goal(statement: "")
        #expect(goal.statement == "")
    }

    @Test("Goal handles long statement")
    func handlesLongStatement() {
        let longStatement = String(repeating: "Objective ", count: 1000)
        let goal = Goal(statement: longStatement)

        #expect(goal.statement.count > 8000)
    }

    @Test("Goal handles zero max iterations")
    func handlesZeroMaxIterations() {
        let goal = Goal(statement: "Test", maxIterations: 0)

        let (completed, ceiling) = goal.progress
        #expect(ceiling == 0)
        #expect(completed == 0)
        #expect(goal.iterations.count >= goal.maxIterations)
    }

    @Test("Goal handles single iteration")
    func handlesSingleIteration() {
        let goal = Goal(statement: "Test", maxIterations: 1)
        #expect(goal.maxIterations == 1)
        #expect(goal.isTerminal == false) // Not terminal until state changes
    }

    @Test("Goal handles many iterations")
    func handlesManyIterations() {
        let goal = Goal(statement: "Test", maxIterations: 1000)
        #expect(goal.maxIterations == 1000)
    }

    @Test("Goal with many iterations tracks progress")
    func tracksManyIterations() {
        var goal = Goal(statement: "Test", maxIterations: 100)

        // Simulate 50 iterations
        for i in 1...50 {
            goal.iterations.append(GoalIteration(
                iteration: i,
                observation: "Iteration \(i)",
                judgement: .progressing
            ))
        }

        let (completed, ceiling) = goal.progress
        #expect(completed == 50)
        #expect(ceiling == 100)
    }

    @Test("Goal lastJudgement with no iterations is nil")
    func lastJudgementNilNoIterations() {
        let goal = Goal(statement: "Test")
        #expect(goal.lastJudgement == nil)
    }

    @Test("Goal timestamps are consistent")
    func timestampsConsistent() {
        let before = Date()
        let goal = Goal(statement: "Test")
        let after = Date()

        #expect(goal.createdAt >= before)
        #expect(goal.createdAt <= after)
        #expect(goal.updatedAt >= before)
        #expect(goal.updatedAt <= after)
    }
}

@Suite("Goal JSON Serialization")
struct GoalJSONTests {

    @Test("Goal serializes to valid JSON")
    func serializesToJSON() throws {
        let goal = Goal(
            statement: "Test JSON",
            parentSessionID: "abc-123",
            maxIterations: 10,
            state: .active
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(goal)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["statement"] as? String == "Test JSON")
        #expect(json?["state"] as? String == "active")
        #expect(json?["maxIterations"] as? Int == 10)
    }

    @Test("Goal deserializes from JSON")
    func deserializesFromJSON() throws {
        let json = """
        {
            "id": "test-id-123",
            "statement": "Deserialized goal",
            "state": "completed",
            "parentSessionID": "parent-456",
            "maxIterations": 25,
            "iterations": [
                {
                    "id": "iter-1",
                    "iteration": 1,
                    "sessionID": "session-1",
                    "observation": "First iteration",
                    "judgement": "progressing",
                    "createdAt": "2024-01-01T00:00:00Z"
                }
            ],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-02T00:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let goal = try decoder.decode(Goal.self, from: json.data(using: .utf8)!)

        #expect(goal.id == "test-id-123")
        #expect(goal.statement == "Deserialized goal")
        #expect(goal.state == .completed)
        #expect(goal.parentSessionID == "parent-456")
        #expect(goal.maxIterations == 25)
        #expect(goal.iterations.count == 1)
        #expect(goal.iterations[0].iteration == 1)
        #expect(goal.iterations[0].judgement == .progressing)
    }
}
