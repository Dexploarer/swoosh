// Tests/SwooshGoalsTests/GoalStoreTests.swift — Goal persistence tests
//
// Tests GoalStoring protocol, InMemoryGoalStore, and FileGoalStore
// implementations for goal persistence.

import Testing
import Foundation
@testable import SwooshGoals

// MARK: - InMemoryGoalStore Tests

@Suite("InMemoryGoalStore")
struct InMemoryGoalStoreTests {

    @Test("Store initializes empty")
    func initializesEmpty() async {
        let store = InMemoryGoalStore()
        let goals = try? await store.listAll()

        #expect(goals?.isEmpty == true)
    }

    @Test("Save adds goal to store")
    func saveAddsGoal() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Test goal")

        try await store.save(goal)

        let retrieved = try await store.get(id: goal.id)
        #expect(retrieved?.id == goal.id)
        #expect(retrieved?.statement == "Test goal")
    }

    @Test("Get returns nil for non-existent goal")
    func getReturnsNilForMissing() async throws {
        let store = InMemoryGoalStore()

        let retrieved = try await store.get(id: "non-existent")

        #expect(retrieved == nil)
    }

    @Test("Update modifies existing goal")
    func updateModifiesGoal() async throws {
        let store = InMemoryGoalStore()
        var goal = Goal(statement: "Original")
        try await store.save(goal)

        goal.statement = "Updated"
        goal.state = .active
        try await store.update(goal)

        let retrieved = try await store.get(id: goal.id)
        #expect(retrieved?.statement == "Updated")
        #expect(retrieved?.state == .active)
        #expect((retrieved?.updatedAt ?? .distantPast) > goal.createdAt)
    }

    @Test("Delete removes goal from store")
    func deleteRemovesGoal() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "To be deleted")
        try await store.save(goal)

        try await store.delete(id: goal.id)

        let retrieved = try await store.get(id: goal.id)
        #expect(retrieved == nil)
    }

    @Test("Delete non-existent goal does not throw")
    func deleteNonExistentSafe() async {
        let store = InMemoryGoalStore()

        await #expect(throws: Never.self) {
            try await store.delete(id: "non-existent")
        }
    }

    @Test("ListAll returns all goals sorted by updatedAt")
    func listAllReturnsSorted() async throws {
        let store = InMemoryGoalStore()

        let goal1 = Goal(statement: "First")
        try await store.save(goal1)

        try await Task.sleep(for: .milliseconds(10))

        let goal2 = Goal(statement: "Second")
        try await store.save(goal2)

        let goals = try await store.listAll()

        #expect(goals.count == 2)
        #expect(goals[0].statement == "Second") // Most recent first
        #expect(goals[1].statement == "First")
    }

    @Test("ListActive returns only pending and active goals")
    func listActiveFilters() async throws {
        let store = InMemoryGoalStore()

        let pending = Goal(statement: "Pending", state: .pending)
        let active = Goal(statement: "Active", state: .active)
        let paused = Goal(statement: "Paused", state: .paused)
        let completed = Goal(statement: "Completed", state: .completed)
        let abandoned = Goal(statement: "Abandoned", state: .abandoned)

        try await store.save(pending)
        try await store.save(active)
        try await store.save(paused)
        try await store.save(completed)
        try await store.save(abandoned)

        let activeGoals = try await store.listActive()

        #expect(activeGoals.count == 2)
        #expect(activeGoals.contains { $0.state == .pending })
        #expect(activeGoals.contains { $0.state == .active })
        #expect(!activeGoals.contains { $0.state == .paused })
        #expect(!activeGoals.contains { $0.state == .completed })
        #expect(!activeGoals.contains { $0.state == .abandoned })
    }

    @Test("AppendIteration adds iteration to goal")
    func appendIterationAdds() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Test")
        try await store.save(goal)

        let iteration = GoalIteration(
            iteration: 1,
            observation: "First iteration",
            judgement: .progressing
        )

        try await store.appendIteration(goalID: goal.id, iteration: iteration)

        let retrieved = try await store.get(id: goal.id)
        #expect(retrieved?.iterations.count == 1)
        #expect(retrieved?.iterations[0].observation == "First iteration")
    }

    @Test("AppendIteration to non-existent goal does nothing")
    func appendIterationNonExistentSafe() async {
        let store = InMemoryGoalStore()
        let iteration = GoalIteration(iteration: 1, observation: "Test", judgement: .progressing)

        await #expect(throws: Never.self) {
            try await store.appendIteration(goalID: "non-existent", iteration: iteration)
        }
    }

    @Test("SetState updates goal state")
    func setStateUpdates() async throws {
        let store = InMemoryGoalStore()
        let goal = Goal(statement: "Test", state: .pending)
        try await store.save(goal)

        try await store.setState(goalID: goal.id, state: .active)

        let retrieved = try await store.get(id: goal.id)
        #expect(retrieved?.state == .active)
        #expect((retrieved?.updatedAt ?? .distantPast) > goal.updatedAt)
    }

    @Test("SetState to non-existent goal does nothing")
    func setStateNonExistentSafe() async {
        let store = InMemoryGoalStore()

        await #expect(throws: Never.self) {
            try await store.setState(goalID: "non-existent", state: .completed)
        }
    }

    @Test("Multiple saves preserve all goals")
    func multipleSavesPreserve() async throws {
        let store = InMemoryGoalStore()

        for i in 1...100 {
            let goal = Goal(statement: "Goal \(i)")
            try await store.save(goal)
        }

        let goals = try await store.listAll()
        #expect(goals.count == 100)
    }

    @Test("Concurrent saves are safe")
    func concurrentSavesSafe() async throws {
        let store = InMemoryGoalStore()

        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let goal = Goal(statement: "Concurrent \(i)")
                    try? await store.save(goal)
                }
            }
        }

        let goals = try await store.listAll()
        #expect(goals.count == 10)
    }
}

// MARK: - FileGoalStore Tests

@Suite("FileGoalStore")
struct FileGoalStoreTests {

    @Test("Store initializes with default URL")
    func initializesWithDefaultURL() {
        let store = FileGoalStore()
        // Should use ~/.swoosh/goals/goals.json
        #expect(store != nil)
    }

    @Test("Store initializes with custom URL")
    func initializesWithCustomURL() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-goals.json")

        let store = FileGoalStore(url: url)
        #expect(store != nil)
    }

    @Test("Save persists goal to file")
    func savePersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-persist-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)
        let goal = Goal(statement: "Persisted goal")

        try await store.save(goal)

        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Create new store instance and verify data loads
        let newStore = FileGoalStore(url: url)
        let retrieved = try await newStore.get(id: goal.id)

        #expect(retrieved?.statement == "Persisted goal")
    }

    @Test("Update modifies and persists goal")
    func updatePersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-update-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)
        var goal = Goal(statement: "Original")
        try await store.save(goal)

        goal.statement = "Updated"
        goal.state = .completed
        try await store.update(goal)

        let newStore = FileGoalStore(url: url)
        let retrieved = try await newStore.get(id: goal.id)

        #expect(retrieved?.statement == "Updated")
        #expect(retrieved?.state == .completed)
    }

    @Test("Delete removes from file")
    func deleteRemoves() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-delete-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)
        let goal = Goal(statement: "To delete")
        try await store.save(goal)

        try await store.delete(id: goal.id)

        let newStore = FileGoalStore(url: url)
        let retrieved = try await newStore.get(id: goal.id)

        #expect(retrieved == nil)
    }

    @Test("ListAll returns sorted goals from file")
    func listAllFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-list-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)

        let goal1 = Goal(statement: "First")
        try await store.save(goal1)
        try await Task.sleep(for: .milliseconds(10))

        let goal2 = Goal(statement: "Second")
        try await store.save(goal2)

        let goals = try await store.listAll()

        #expect(goals.count == 2)
        #expect(goals[0].statement == "Second")
    }

    @Test("ListActive filters from file")
    func listActiveFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-active-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)

        let active = Goal(statement: "Active", state: .active)
        let completed = Goal(statement: "Completed", state: .completed)

        try await store.save(active)
        try await store.save(completed)

        let activeGoals = try await store.listActive()

        #expect(activeGoals.count == 1)
        #expect(activeGoals[0].statement == "Active")
    }

    @Test("AppendIteration persists to file")
    func appendIterationPersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-iter-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)
        let goal = Goal(statement: "Test")
        try await store.save(goal)

        let iteration = GoalIteration(
            iteration: 1,
            observation: "Progress",
            judgement: .progressing
        )
        try await store.appendIteration(goalID: goal.id, iteration: iteration)

        let newStore = FileGoalStore(url: url)
        let retrieved = try await newStore.get(id: goal.id)

        #expect(retrieved?.iterations.count == 1)
    }

    @Test("SetState persists to file")
    func setStatePersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileGoalStore(url: url)
        let goal = Goal(statement: "Test", state: .pending)
        try await store.save(goal)

        try await store.setState(goalID: goal.id, state: .active)

        let newStore = FileGoalStore(url: url)
        let retrieved = try await newStore.get(id: goal.id)

        #expect(retrieved?.state == .active)
    }

    @Test("Handles corrupted file gracefully")
    func handlesCorruptedFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write invalid JSON
        try "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = FileGoalStore(url: url)

        // Should throw when trying to load
        await #expect(throws: Error.self) {
            _ = try await store.listAll()
        }
    }

    @Test("Creates directories if needed")
    func createsDirectories() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let subDir = tempDir.appendingPathComponent("nested-\(UUID().uuidString)/deep")
        let url = subDir.appendingPathComponent("goals.json")
        defer { try? FileManager.default.removeItem(at: subDir) }

        let store = FileGoalStore(url: url)
        let goal = Goal(statement: "Test")

        try await store.save(goal)

        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: - GoalStoring Protocol Tests

@Suite("GoalStoring Protocol")
struct GoalStoringProtocolTests {

    @Test("InMemoryGoalStore conforms to GoalStoring")
    func inMemoryConforms() {
        let _: any GoalStoring.Type = InMemoryGoalStore.self
        #expect(true)
    }

    @Test("FileGoalStore conforms to GoalStoring")
    func fileConforms() {
        let _: any GoalStoring.Type = FileGoalStore.self
        #expect(true)
    }

    @Test("Can use GoalStoring existential")
    func existentialWorks() async throws {
        let stores: [any GoalStoring] = [
            InMemoryGoalStore(),
            FileGoalStore()
        ]

        for store in stores {
            let goal = Goal(statement: "Test")
            try await store.save(goal)

            let retrieved = try await store.get(id: goal.id)
            #expect(retrieved?.id == goal.id)
        }
    }
}
