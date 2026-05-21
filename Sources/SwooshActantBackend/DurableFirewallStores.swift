// SwooshActantBackend/DurableFirewallStores.swift — ActantDB-durable tool audit + approvals — 0.4B
//
// The in-memory `SwooshAuditLog` / `InMemoryApprovalStore` lose the
// tool-call audit trail and the pending-approval queue on every daemon
// restart — which silently breaks engineering rule #3 ("every agent step
// is logged") and rule #5 (`/why` audit inspection).
//
// These two stores ride the ActantDB ledger instead. Each record is a
// sentinel-wrapped agent message on a dedicated session — the same shape
// `ActantAgent.Auditor` uses — so Studio and replay see them natively and
// they survive restarts.

import Foundation
import ActantDB
import ActantAgent
import SwooshTools
import SwooshApprovals

// MARK: - Generic ledger-backed append log

/// Append-only log of `Codable` records on a dedicated ActantDB session.
/// `append` writes one sentinel-wrapped agent message; `all` reads every
/// record back in chronological order.
///
/// Wire shape of each log message's text:
///
///     {"<sentinelKey>": {"v":1, "r": <encoded Record>}}
actor LedgerLog<Record: Codable & Sendable> {
    private let backend: AgentBackend
    private let sessionID: String
    private let sentinelKey: String
    private var sessionEnsured = false

    init(backend: AgentBackend, sessionID: String, sentinelKey: String) {
        self.backend = backend
        self.sessionID = sessionID
        self.sentinelKey = sentinelKey
    }

    func append(_ record: Record) async throws {
        try await ensureSession()
        let client = await backend.client
        let workspaceID = await backend.workspaceID
        let actorID = await backend.actorID

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let recordData = try encoder.encode(record)
        let recordValue = try JSONDecoder().decode(ActantDB.JSONValue.self, from: recordData)
        let envelope: ActantDB.JSONValue = .object([
            sentinelKey: .object(["v": .int(1), "r": recordValue]),
        ])
        let envelopeData = try encoder.encode(envelope)
        guard let text = String(data: envelopeData, encoding: .utf8) else {
            throw ActantError.transport("LedgerLog.append: envelope is not UTF-8")
        }
        _ = try await client.appendAgentMessage(
            workspaceID: workspaceID, actorID: actorID,
            sessionID: sessionID, text: text
        )
    }

    /// Every record in the log, oldest-first. Returns `[]` if the session
    /// has no events yet or the daemon cannot reach ActantDB.
    func all() async -> [Record] {
        let client = await backend.client
        guard let events = try? await client.events(sessionID: sessionID) else { return [] }
        let decoder = JSONDecoder()
        var out: [Record] = []
        for event in events {
            guard let payload = try? event.parsedPayload(),
                  case let .object(outer) = payload,
                  case let .string(text)? = outer["text"],
                  let data = text.data(using: .utf8),
                  let envelope = try? decoder.decode(ActantDB.JSONValue.self, from: data),
                  case let .object(envObj) = envelope,
                  case let .object(inner)? = envObj[sentinelKey],
                  let recordValue = inner["r"],
                  let recordData = try? JSONEncoder().encode(recordValue),
                  let record = try? decoder.decode(Record.self, from: recordData)
            else { continue }
            out.append(record)
        }
        return out
    }

    private func ensureSession() async throws {
        if sessionEnsured { return }
        let client = await backend.client
        let workspaceID = await backend.workspaceID
        let actorID = await backend.actorID
        _ = try await client.createSession(
            workspaceID: workspaceID, actorID: actorID, sessionID: sessionID
        )
        sessionEnsured = true
    }
}

// MARK: - Durable tool audit log

/// `AuditLogging` backed by the ActantDB ledger. Tool-call audit entries
/// survive daemon restarts instead of vanishing with process memory.
public struct ActantAuditLog: SwooshTools.AuditLogging {
    private let log: LedgerLog<AuditEntry>

    public init(backend: AgentBackend) {
        self.log = LedgerLog(
            backend: backend,
            sessionID: "_swoosh_tool_audit",
            sentinelKey: "_swoosh_tool_audit"
        )
    }

    public func append(_ event: AuditEntry) async throws {
        try await log.append(event)
    }

    public func tail(limit: Int) async -> [AuditEntry] {
        Array(await log.all().suffix(max(0, limit)))
    }

    public func search(query: String, limit: Int) async -> [AuditEntry] {
        let needle = query.lowercased()
        let matches = await log.all().filter { entry in
            entry.detail.lowercased().contains(needle)
                || (entry.toolName?.lowercased().contains(needle) ?? false)
                || entry.kind.rawValue.lowercased().contains(needle)
        }
        return Array(matches.suffix(max(0, limit)))
    }

    public func getEvent(id: String) async -> AuditEntry? {
        await log.all().first { $0.id == id }
    }
}

// MARK: - Durable approval store

/// `ApprovalStoring` backed by the ActantDB ledger. The pending-approval
/// queue survives daemon restarts. The log is append-only — a `resolve`
/// appends a new version of the record, and reads reduce to the latest
/// version per approval id.
public struct ActantApprovalStore: SwooshApprovals.ApprovalStoring {
    private let log: LedgerLog<ApprovalRecord>

    public init(backend: AgentBackend) {
        self.log = LedgerLog(
            backend: backend,
            sessionID: "_swoosh_approvals",
            sentinelKey: "_swoosh_approval"
        )
    }

    /// Reduce the append-only log to current state — last write per id wins.
    private func current() async -> [String: ApprovalRecord] {
        var latest: [String: ApprovalRecord] = [:]
        for record in await log.all() { latest[record.id] = record }
        return latest
    }

    public func save(_ approval: ApprovalRecord) async throws {
        try await log.append(approval)
    }

    public func get(id: String) async -> ApprovalRecord? {
        await current()[id]
    }

    public func listPending(sessionID: String?) async -> [ApprovalRecord] {
        await current().values
            .filter { $0.status == .pending }
            .filter { sessionID == nil || $0.sessionID == sessionID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func resolve(
        id: String,
        status: ApprovalStatus,
        resolvedBy: ToolCallOrigin,
        reason: String?
    ) async throws {
        guard var record = await current()[id] else {
            throw ApprovalError.approvalNotFound(id)
        }
        guard record.status == .pending else {
            throw ApprovalError.alreadyResolved(id)
        }
        record.status = status
        record.resolvedAt = Date()
        record.resolvedBy = resolvedBy
        record.denyReason = reason
        try await log.append(record)
    }

    public func isApprovedForSession(toolName: String, sessionID: String) async -> Bool {
        await current().values.contains { record in
            record.toolName == toolName
                && record.sessionID == sessionID
                && record.status == .approvedForSession
        }
    }
}
