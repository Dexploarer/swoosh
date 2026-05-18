// SwooshObservability/CheckpointManager.swift — Save/restore agent state
//
// Hermes-style checkpointing for long-running tasks. Saves agent state
// periodically so work can be resumed after crashes, timeouts, or
// manual interrupts.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Checkpoint
// ═══════════════════════════════════════════════════════════════════

/// A serializable snapshot of agent state at a point in time.
public struct Checkpoint: Codable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let traceID: String?
    public let label: String                 // Human-readable label
    public let turnIndex: Int
    public let state: CheckpointState
    public let timestamp: Date

    /// Opaque state blob — the agent serializes whatever it needs.
    public struct CheckpointState: Codable, Sendable {
        public var messages: Data?           // Conversation history
        public var toolResults: Data?        // Accumulated tool results
        public var workflowProgress: Data?   // Workflow step index + data
        public var metadata: [String: String]

        public init(messages: Data? = nil, toolResults: Data? = nil,
                    workflowProgress: Data? = nil, metadata: [String: String] = [:]) {
            self.messages = messages
            self.toolResults = toolResults
            self.workflowProgress = workflowProgress
            self.metadata = metadata
        }
    }

    public init(sessionID: String, traceID: String? = nil,
                label: String, turnIndex: Int, state: CheckpointState) {
        self.id = UUID().uuidString
        self.sessionID = sessionID
        self.traceID = traceID
        self.label = label
        self.turnIndex = turnIndex
        self.state = state
        self.timestamp = Date()
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Checkpoint store protocol
// ═══════════════════════════════════════════════════════════════════

public protocol CheckpointStoring: Sendable {
    func save(_ checkpoint: Checkpoint) async throws
    func load(sessionID: String) async throws -> Checkpoint?
    func loadAll(sessionID: String) async throws -> [Checkpoint]
    func delete(id: String) async throws
    func prune(sessionID: String, keepLast: Int) async throws
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - File-based checkpoint store
// ═══════════════════════════════════════════════════════════════════

/// Stores checkpoints as JSON files in ~/.swoosh/checkpoints/.
public actor FileCheckpointStore: CheckpointStoring {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/checkpoints")
    }

    public func save(_ checkpoint: Checkpoint) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(checkpoint.id).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(checkpoint)
        try data.write(to: url, options: .atomic)
    }

    public func load(sessionID: String) async throws -> Checkpoint? {
        try await loadAll(sessionID: sessionID).last
    }

    public func loadAll(sessionID: String) async throws -> [Checkpoint] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var checkpoints: [Checkpoint] = []
        for file in files {
            let data = try Data(contentsOf: file)
            let checkpoint = try decoder.decode(Checkpoint.self, from: data)
            if checkpoint.sessionID == sessionID {
                checkpoints.append(checkpoint)
            }
        }
        return checkpoints.sorted { $0.timestamp < $1.timestamp }
    }

    public func delete(id: String) async throws {
        let url = directory.appendingPathComponent("\(id).json")
        try FileManager.default.removeItem(at: url)
    }

    public func prune(sessionID: String, keepLast: Int) async throws {
        let all = try await loadAll(sessionID: sessionID)
        let toDelete = all.dropLast(keepLast)
        for checkpoint in toDelete {
            try? await delete(id: checkpoint.id)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Checkpoint manager
// ═══════════════════════════════════════════════════════════════════

/// High-level checkpoint manager with auto-save support.
public actor CheckpointManager {
    private let store: any CheckpointStoring
    private let autoSaveInterval: Int        // Save every N turns
    private let maxCheckpoints: Int          // Keep last N per session
    private var turnsSinceLastCheckpoint: Int = 0

    public init(store: any CheckpointStoring = FileCheckpointStore(),
                autoSaveInterval: Int = 5,
                maxCheckpoints: Int = 10) {
        self.store = store
        self.autoSaveInterval = autoSaveInterval
        self.maxCheckpoints = maxCheckpoints
    }

    /// Record a turn; auto-save checkpoint if interval reached.
    public func recordTurn(
        sessionID: String,
        turnIndex: Int,
        stateBuilder: () -> Checkpoint.CheckpointState
    ) async throws {
        turnsSinceLastCheckpoint += 1

        if turnsSinceLastCheckpoint >= autoSaveInterval {
            let state = stateBuilder()
            let checkpoint = Checkpoint(
                sessionID: sessionID,
                label: "auto-\(turnIndex)",
                turnIndex: turnIndex,
                state: state
            )
            try await store.save(checkpoint)
            try await store.prune(sessionID: sessionID, keepLast: maxCheckpoints)
            turnsSinceLastCheckpoint = 0
        }
    }

    /// Force a named checkpoint.
    public func saveCheckpoint(
        sessionID: String,
        label: String,
        turnIndex: Int,
        state: Checkpoint.CheckpointState
    ) async throws {
        let checkpoint = Checkpoint(
            sessionID: sessionID,
            label: label,
            turnIndex: turnIndex,
            state: state
        )
        try await store.save(checkpoint)
    }

    /// Restore from the latest checkpoint.
    public func restore(sessionID: String) async throws -> Checkpoint? {
        try await store.load(sessionID: sessionID)
    }

    /// List all checkpoints for a session.
    public func list(sessionID: String) async throws -> [Checkpoint] {
        try await store.loadAll(sessionID: sessionID)
    }
}
