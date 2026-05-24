// SwooshGoals/GoalStore.swift — Persistence interface for goals — 0.1A
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

public actor FileGoalStore: GoalStoring {
    private let url: URL
    private var loaded = false
    private var goals: [String: Goal] = [:]

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/goals/goals.json")
    }

    public func save(_ goal: Goal) throws {
        try ensureLoaded()
        goals[goal.id] = goal
        try persist()
    }

    public func update(_ goal: Goal) throws {
        try ensureLoaded()
        var updated = goal
        updated.updatedAt = Date()
        goals[goal.id] = updated
        try persist()
    }

    public func get(id: String) throws -> Goal? {
        try ensureLoaded()
        return goals[id]
    }

    public func delete(id: String) throws {
        try ensureLoaded()
        goals.removeValue(forKey: id)
        try persist()
    }

    public func listAll() throws -> [Goal] {
        try ensureLoaded()
        return goals.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func listActive() throws -> [Goal] {
        try listAll().filter { $0.state == .active || $0.state == .pending }
    }

    public func appendIteration(goalID: String, iteration: GoalIteration) throws {
        try ensureLoaded()
        guard var goal = goals[goalID] else { return }
        goal.iterations.append(iteration)
        goal.updatedAt = Date()
        goals[goalID] = goal
        try persist()
    }

    public func setState(goalID: String, state: GoalState) throws {
        try ensureLoaded()
        guard var goal = goals[goalID] else { return }
        goal.state = state
        goal.updatedAt = Date()
        goals[goalID] = goal
        try persist()
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder.swooshGoals.decode(GoalStoreSnapshot.self, from: data)
            goals = Dictionary(uniqueKeysWithValues: snapshot.goals.map { ($0.id, $0) })
        }
        loaded = true
    }

    private func persist() throws {
        let snapshot = GoalStoreSnapshot(goals: goals.values.sorted { $0.updatedAt > $1.updatedAt })
        let data = try JSONEncoder.swooshGoals.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

private struct GoalStoreSnapshot: Codable, Sendable {
    let goals: [Goal]
}

private extension JSONEncoder {
    static var swooshGoals: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var swooshGoals: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
