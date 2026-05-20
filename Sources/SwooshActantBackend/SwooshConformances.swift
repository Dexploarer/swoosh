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
import SwooshTools

public typealias CoreChatMessage = SwooshCore.ChatMessage
public typealias CoreChatRole = SwooshCore.ChatRole

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

extension ActantAgent.MemoryStore: SwooshTools.MemoryToolStoring {
    public func listApproved(
        category: SwooshTools.MemoryCategory?,
        limit: Int?
    ) async throws -> [SwooshTools.ApprovedMemory] {
        let rows = try await listApproved().compactMap { row -> SwooshTools.ApprovedMemory? in
            let memory = row.asToolMemory
            guard category == nil || memory.category == category else { return nil }
            return memory
        }
        return limit.map { Array(rows.prefix(max(0, $0))) } ?? rows
    }

    public func searchApproved(
        query: String,
        category: SwooshTools.MemoryCategory?,
        limit: Int?
    ) async throws -> [SwooshTools.ApprovedMemorySearchResult] {
        let needle = query.normalizedForActantMemorySearch()
        guard !needle.isEmpty else { return [] }
        let results = try await listApproved(category: category, limit: nil).compactMap { memory -> SwooshTools.ApprovedMemorySearchResult? in
            let haystack = memory.text.normalizedForActantMemorySearch()
            guard haystack.contains(needle) else { return nil }
            let score = haystack == needle ? 1.0 : max(0.2, Double(needle.count) / Double(max(haystack.count, 1)))
            return SwooshTools.ApprovedMemorySearchResult(memory: memory, score: score, reason: "text match")
        }.sorted { $0.score > $1.score }
        return limit.map { Array(results.prefix(max(0, $0))) } ?? results
    }

    public func getApproved(id: String) async throws -> SwooshTools.ApprovedMemory? {
        try await listApproved().first { $0.id == id }?.asToolMemory
    }

    public func listCandidates(
        status: SwooshTools.CandidateStatus?,
        limit: Int?
    ) async throws -> [SwooshTools.MemoryCandidate] {
        let pending = try await listPending().map(\.asToolCandidate)
        let rows = pending.filter { status == nil || $0.status == status }
        return limit.map { Array(rows.prefix(max(0, $0))) } ?? rows
    }

    public func getCandidate(id: String) async throws -> SwooshTools.MemoryCandidate? {
        try await listPending().first { $0.id == id }?.asToolCandidate
    }

    public func propose(_ input: SwooshTools.ProposeMemoryCandidateInput) async throws -> String {
        try await propose(
            text: input.text,
            category: input.category.rawValue,
            sensitivity: input.sensitivity.asActantSensitivity,
            confidence: input.confidence,
            evidence: input.evidence.asActantJSON
        )
    }

    public func approve(candidateID: String, finalText: String?) async throws -> String {
        if let finalText {
            let candidate = try await getCandidate(id: candidateID)
            _ = try await propose(SwooshTools.ProposeMemoryCandidateInput(
                text: finalText,
                category: candidate?.category ?? .fact,
                sensitivity: candidate?.sensitivity ?? .normal,
                confidence: candidate?.confidence ?? 1.0,
                evidence: candidate?.evidence ?? []
            ))
        }
        try await approve(candidateID: candidateID)
        return candidateID
    }

    public func edit(candidateID: String, newText: String, newCategory: SwooshTools.MemoryCategory?, newSensitivity: SwooshTools.Sensitivity?) async throws {
        guard let candidate = try await getCandidate(id: candidateID) else {
            throw SwooshTools.ToolError.notFound(candidateID)
        }
        _ = try await propose(SwooshTools.ProposeMemoryCandidateInput(
            text: newText,
            category: newCategory ?? candidate.category,
            sensitivity: newSensitivity ?? candidate.sensitivity,
            confidence: candidate.confidence,
            evidence: candidate.evidence
        ))
        try await reject(candidateID: candidateID, reason: "superseded by edited candidate")
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

    public func appendMessage(sessionID: String, message: CoreChatMessage) async throws {
        try await ensureSession(sessionID: sessionID)
        try await session(for: sessionID).appendMessage(message)
    }

    public func loadTranscript(sessionID: String) async throws -> [CoreChatMessage] {
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

    private func session(for sessionID: String) -> ActantAgent.Session<CoreChatMessage> {
        ActantAgent.Session<CoreChatMessage>(
            backend: backend, sessionID: sessionID,
            encode: { msg in (role: role(from: msg.role), text: msg.content) },
            decode: { role, text, date in
                CoreChatMessage(role: chatRole(from: role), content: text, createdAt: date)
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

private func role(from chat: CoreChatRole) -> ActantAgent.SessionRole {
    switch chat { case .user: .user; case .assistant: .assistant; case .tool: .tool; case .system: .system }
}

private func chatRole(from session: ActantAgent.SessionRole) -> CoreChatRole {
    switch session { case .user: .user; case .assistant: .assistant; case .tool: .tool; case .system: .system }
}

private extension ActantDB.ApprovedMemory {
    var asToolMemory: SwooshTools.ApprovedMemory {
        SwooshTools.ApprovedMemory(
            id: id,
            text: text,
            category: SwooshTools.MemoryCategory(rawValue: category) ?? .fact,
            sensitivity: sensitivity.asToolSensitivity,
            confidence: confidence ?? 1.0,
            createdAt: createdAt.asISO8601Date ?? Date(),
            lastUsedAt: lastUsedAt?.asISO8601Date
        )
    }
}

private extension ActantDB.MemoryCandidate {
    var asToolCandidate: SwooshTools.MemoryCandidate {
        SwooshTools.MemoryCandidate(
            id: id,
            text: text,
            category: SwooshTools.MemoryCategory(rawValue: category) ?? .fact,
            sensitivity: sensitivity.asToolSensitivity,
            confidence: confidence,
            evidence: [],
            status: SwooshTools.CandidateStatus(rawValue: status) ?? .pending,
            createdAt: createdAt.asISO8601Date ?? Date()
        )
    }
}

private extension ActantDB.Sensitivity {
    var asToolSensitivity: SwooshTools.Sensitivity {
        switch self {
        case .public, .low:
            return .normal
        case .medium, .high:
            return .sensitive
        case .secret:
            return .secret
        }
    }
}

private extension SwooshTools.Sensitivity {
    var asActantSensitivity: ActantDB.Sensitivity {
        switch self {
        case .normal:
            return .low
        case .sensitive:
            return .medium
        case .secret:
            return .secret
        }
    }
}

private extension [SwooshTools.EvidencePointer] {
    var asActantJSON: ActantDB.JSONValue {
        let payload = map { pointer in
            ActantDB.JSONValue.object([
                "source_id": .string(pointer.sourceID),
                "record_id": pointer.recordID.map(ActantDB.JSONValue.string) ?? .null,
                "session_id": pointer.sessionID.map(ActantDB.JSONValue.string) ?? .null,
                "description": .string(pointer.description),
            ])
        }
        return .array(payload)
    }
}

private extension String {
    var asISO8601Date: Date? {
        ISO8601DateFormatter().date(from: self)
    }

    func normalizedForActantMemorySearch() -> String {
        split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
