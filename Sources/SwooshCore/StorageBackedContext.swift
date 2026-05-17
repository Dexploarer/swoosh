// SwooshCore/StorageBackedContext.swift — Concrete protocol implementations
//
// Bridges SwooshStorage (SQLite) to the AgentKernel protocols.
// These load ONLY approved memories, never rejected candidates or raw records.

import Foundation
import SwooshStorage

// MARK: - Memory context loader (approved only)

/// Loads approved memories from SwooshStateStore.
/// Rejected candidates and raw Scout records are NEVER returned.
public final class StorageMemoryLoader: MemoryContextLoading, @unchecked Sendable {
    private let store: SwooshStateStore

    public init(store: SwooshStateStore) {
        self.store = store
    }

    public func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)] {
        let memories = try await store.listApprovedMemories()
        return memories.map { (id: $0.id, text: $0.text, category: $0.category) }
    }
}

// MARK: - Setup report loader

public final class StorageReportLoader: SetupReportLoading, @unchecked Sendable {
    private let store: SwooshStateStore

    public init(store: SwooshStateStore) {
        self.store = store
    }

    public func loadLatestSetupReport() async throws -> String? {
        try await store.latestSetupReport()?.content
    }
}

// MARK: - Permission summarizer

public final class StoragePermissionSummarizer: PermissionSummarizing, @unchecked Sendable {
    private let store: SwooshStateStore

    public init(store: SwooshStateStore) {
        self.store = store
    }

    public func permissionSummary() async throws -> String {
        // Generate from actual permission state
        // For now, return safe defaults
        """
        Granted: deviceProfileRead, installedAppsRead, runningAppsRead
        Pending: selectedFolderRead, calendarRead
        Denied: browserHistoryRead, shellRun, contactsRead
        """
    }
}

// MARK: - Session store (in-memory for now)

/// Simple in-memory session store. Persistent storage is a follow-up.
public actor InMemorySessionStore: SessionStoring {
    private var sessions: [String: [ChatMessage]] = [:]

    public init() {}

    public func appendMessage(sessionID: String, message: ChatMessage) async throws {
        var transcript = sessions[sessionID] ?? []
        transcript.append(message)
        sessions[sessionID] = transcript
    }

    public func loadTranscript(sessionID: String) async throws -> [ChatMessage] {
        sessions[sessionID] ?? []
    }
}

// MARK: - Response audit logger (in-memory for now)

/// Stores response audit records for /why.
public actor InMemoryResponseAuditor: ResponseAuditing {
    private var records: [String: [ResponseAuditRecord]] = [:]

    public init() {}

    public func logResponseAudit(_ audit: ResponseAuditRecord) async throws {
        var sessionRecords = records[audit.sessionID] ?? []
        sessionRecords.append(audit)
        records[audit.sessionID] = sessionRecords
    }

    public func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord? {
        records[sessionID]?.last
    }
}

// MARK: - In-memory test implementations

/// In-memory memory loader for tests.
public final class InMemoryMemoryLoader: MemoryContextLoading, @unchecked Sendable {
    private var memories: [(id: String, text: String, category: String)]

    public init(memories: [(id: String, text: String, category: String)] = []) {
        self.memories = memories
    }

    public func add(id: String, text: String, category: String) {
        memories.append((id: id, text: text, category: category))
    }

    public func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)] {
        memories
    }
}

/// In-memory report loader for tests.
public final class InMemoryReportLoader: SetupReportLoading, @unchecked Sendable {
    public var report: String?

    public init(report: String? = nil) {
        self.report = report
    }

    public func loadLatestSetupReport() async throws -> String? {
        report
    }
}

/// In-memory permission summarizer for tests.
public final class InMemoryPermSummarizer: PermissionSummarizing, @unchecked Sendable {
    public var summary: String

    public init(summary: String = "Granted: deviceProfileRead\nDenied: browserHistoryRead") {
        self.summary = summary
    }

    public func permissionSummary() async throws -> String {
        summary
    }
}
