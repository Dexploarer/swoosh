// SwooshCore/InMemoryContext.swift — In-memory protocol implementations (0.4A)
//
// Default implementations used when the agent runs without a persistent
// backend (unit tests, REPL exploration, the in-process Swoosh.configure
// path when ACTANT_BASE_URL is unset). Production wires through
// SwooshActantBackend's conformance extensions over ActantAgent instead.

import Foundation

// MARK: - Session store (in-memory)

/// Simple in-memory session store. Persistent storage is provided by
/// `SwooshActantBackend.SwooshSessionStore` when ActantDB is configured.
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

// MARK: - Response audit logger (in-memory)

/// Stores response audit records for `/why`.
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

public final class InMemoryReportLoader: SetupReportLoading, @unchecked Sendable {
    public var report: String?

    public init(report: String? = nil) {
        self.report = report
    }

    public func loadLatestSetupReport() async throws -> String? {
        report
    }
}

public final class InMemoryPermSummarizer: PermissionSummarizing, @unchecked Sendable {
    public var summary: String

    public init(summary: String = "Granted: deviceProfileRead\nDenied: browserHistoryRead") {
        self.summary = summary
    }

    public func permissionSummary() async throws -> String {
        summary
    }
}
