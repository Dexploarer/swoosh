// SwooshActantBackend/SwooshConformances.swift — ActantAgent ↔ SwooshCore (0.4A)
//
// One file. Bridge ActantAgent's facade types to SwooshCore's protocols. No
// adapter classes — direct conformances where the type shape matches, and
// tiny structs that delegate per-call where SwooshCore's API takes a
// sessionID the ActantAgent facade fixes at construction.

import Foundation
import ActantDB
import ActantAgent
import SwooshCore

// MARK: - Direct conformances (workspace-scoped, no sessionID)

extension ActantAgent.MemoryStore: SwooshCore.MemoryContextLoading {
    public func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)] {
        try await listApproved().map { ($0.id, $0.text, $0.category) }
    }
}

extension ActantAgent.MemoryStore: SwooshCore.SetupReportLoading {
    public func loadLatestSetupReport() async throws -> String? {
        // Facade method missing on ActantAgent today; reach through the backend.
        try await backend.client.latestSetupReport(workspaceID: backend.workspaceID)?.content
    }
}

extension ActantAgent.ApprovalCenter: SwooshCore.PermissionSummarizing {
    public func permissionSummary() async throws -> String {
        // Facade method missing on ActantAgent today; reach through the backend.
        let rows = try await backend.client.permissions(workspaceID: backend.workspaceID)
        guard !rows.isEmpty else { return "No permissions granted." }
        return rows.map { "• \($0.permission) (\($0.sensitivityCeiling.rawValue))" }
            .joined(separator: "\n")
    }
}

// MARK: - Per-call adapters (sessionID arrives in the SwooshCore call,
//        ActantAgent fixes it at construction — re-build Session per call).

public actor SwooshSessionStore: SwooshCore.SessionStoring {
    public let backend: AgentBackend
    private var initializedSessionIDs: Set<String> = []

    public init(backend: AgentBackend) { self.backend = backend }

    public func appendMessage(sessionID: String, message: ChatMessage) async throws {
        try await ensureSession(sessionID: sessionID)
        try await session(for: sessionID).appendMessage(message)
    }

    public func loadTranscript(sessionID: String) async throws -> [ChatMessage] {
        try await session(for: sessionID).loadTranscript()
    }

    private func ensureSession(sessionID: String) async throws {
        if initializedSessionIDs.contains(sessionID) { return }
        let client = await backend.client
        let workspaceID = await backend.workspaceID
        let actorID = await backend.actorID
        _ = try await client.createSession(
            workspaceID: workspaceID,
            actorID: actorID,
            sessionID: sessionID
        )
        initializedSessionIDs.insert(sessionID)
    }

    private func session(for sessionID: String) -> ActantAgent.Session<ChatMessage> {
        ActantAgent.Session<ChatMessage>(
            backend: backend, sessionID: sessionID,
            encode: { msg in (role: role(from: msg.role), text: msg.content) },
            decode: { role, text, date in
                ChatMessage(role: chatRole(from: role), content: text, createdAt: date)
            }
        )
    }
}

public struct SwooshResponseAuditor: SwooshCore.ResponseAuditing, Sendable {
    public let backend: AgentBackend
    public let sentinelKey: String
    public init(backend: AgentBackend, sentinelKey: String = "_swoosh_audit") {
        self.backend = backend; self.sentinelKey = sentinelKey
    }

    public func logResponseAudit(_ audit: ResponseAuditRecord) async throws {
        try await auditor(for: audit.sessionID).log(audit)
    }

    public func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord? {
        try await auditor(for: sessionID).last()
    }

    private func auditor(for sessionID: String) -> ActantAgent.Auditor<ResponseAuditRecord> {
        ActantAgent.Auditor<ResponseAuditRecord>(
            backend: backend, sessionID: sessionID, sentinelKey: sentinelKey
        )
    }
}

// MARK: - Role translation

private func role(from chat: ChatRole) -> ActantAgent.SessionRole {
    switch chat { case .user: .user; case .assistant: .assistant; case .tool: .tool; case .system: .system }
}

private func chatRole(from session: ActantAgent.SessionRole) -> ChatRole {
    switch session { case .user: .user; case .assistant: .assistant; case .tool: .tool; case .system: .system }
}
