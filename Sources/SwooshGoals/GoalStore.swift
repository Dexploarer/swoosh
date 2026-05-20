// SwooshGoals/GoalStore.swift — Persistence interface for goals
//
// Same shape as SwooshSkills.SkillStoring — a protocol with a simple
// in-memory default. ActantDB-backed conformance lives in
// SwooshActantBackend so iOS and the daemon share the same goal queue
// once sync is live.

import Foundation

public protocol GoalStoring: Sendable {
    func save(_ goal: Goal) async throws
    func update(_ goal: Goal) async throws
    func get(id: String) async throws -> Goal?
    func delete(id: String) async throws
    func listAll() async throws -> [Goal]
    func listActive() async throws -> [Goal]
    func appendIteration(goalID: String, iteration: GoalIteration) async throws
    func setState(goalID: String, state: GoalState) async throws
}

/// In-memory store. Fine for tests and as the default until the
/// ActantDB-backed conformance is wired.
public actor InMemoryGoalStore: GoalStoring {
    private var goals: [String: Goal] = [:]

    public init() {}

    public func save(_ goal: Goal) async throws {
        goals[goal.id] = goal
    }

    public func update(_ goal: Goal) async throws {
        var updated = goal
        updated.updatedAt = Date()
        goals[goal.id] = updated
    }

    public func get(id: String) async throws -> Goal? {
        goals[id]
    }

    public func delete(id: String) async throws {
        goals.removeValue(forKey: id)
    }

    public func listAll() async throws -> [Goal] {
        Array(goals.values).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func listActive() async throws -> [Goal] {
        try await listAll().filter { $0.state == .active || $0.state == .pending }
    }

    public func appendIteration(goalID: String, iteration: GoalIteration) async throws {
        guard var goal = goals[goalID] else { return }
        goal.iterations.append(iteration)
        goal.updatedAt = Date()
        goals[goalID] = goal
    }

    public func setState(goalID: String, state: GoalState) async throws {
        guard var goal = goals[goalID] else { return }
        goal.state = state
        goal.updatedAt = Date()
        goals[goalID] = goal
    }
}
