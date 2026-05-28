// SwooshStorage/SQLiteMemoryContextLoader.swift — Bridge adapter — 0.9S
//
// Adapts SQLiteMemoryStore (MemoryToolStoring) to MemoryContextLoading
// so the AgentKernel can load approved memories for prompt injection
// without depending on the full tool-store interface.

import Foundation
import SwooshCore
import SwooshTools

/// Loads approved memories from the SQLite store for prompt injection.
public final class SQLiteMemoryContextLoader: MemoryContextLoading, @unchecked Sendable {
    private let memoryStore: SQLiteMemoryStore

    public init(memoryStore: SQLiteMemoryStore) {
        self.memoryStore = memoryStore
    }

    public func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)] {
        let memories = try await memoryStore.listApproved(category: nil, limit: nil)
        return memories.map { (id: $0.id, text: $0.text, category: $0.category.rawValue) }
    }
}
