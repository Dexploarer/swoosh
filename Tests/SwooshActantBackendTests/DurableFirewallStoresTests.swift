// DurableFirewallStoresTests.swift — Round-trip the ActantDB-durable
// tool-audit and approval stores through the mock transport.
//
// These prove the durability code path end to end: a record is
// sentinel-wrapped and appended to the ledger, and read back by
// scanning + decoding ledger events — including the append-only
// "latest record per id wins" reduction the approval store relies on.

import Foundation
import Testing
@testable import SwooshActantBackend
import ActantDB
import ActantAgent
import SwooshTools
import SwooshApprovals

// MARK: - Helpers

private func makeBackend(session: URLSession) -> AgentBackend {
    AgentBackend(
        client: ActantClient(baseURL: URL(string: "http://local-diagnostic")!, urlSession: session),
        workspaceID: "ws_test", actorID: "act_test"
    )
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var isRaised: Bool { lock.withLock { raised } }
    func raise() { lock.withLock { raised = true } }
}

/// Build a `/v1/events` response body whose agent_message events each
/// carry one sentinel-wrapped record — the exact shape `LedgerLog` writes.
private func ledgerEvents<R: Encodable>(_ records: [R], sentinelKey: String) throws -> Data {
    var events: [[String: Any]] = []
    for (idx, record) in records.enumerated() {
        let recordData = try JSONEncoder().encode(record)
        let recordValue = try JSONSerialization.jsonObject(with: recordData)
        let envelope: [String: Any] = [sentinelKey: ["v": 1, "r": recordValue]]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let envelopeStr = String(data: envelopeData, encoding: .utf8) ?? "{}"
        let payloadObj: [String: Any] = ["message_id": "m_\(idx)", "text": envelopeStr]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObj)
        let payloadStr = String(data: payloadData, encoding: .utf8) ?? "{}"
        events.append([
            "id": "evt_\(idx)",
            "workspace_id": "ws_test", "actor_id": "act_test", "session_id": "s_ledger",
            "parent_event_id": NSNull(), "event_type": "agent_message",
            "causality_kind": "observation", "sensitivity": "low",
            "authority_scope_id": NSNull(),
            "payload_inline": payloadStr, "payload_ref": NSNull(),
            "payload_hash": "h\(idx)", "event_hash": "eh\(idx)",
            "created_at": "2026-05-20T12:00:0\(idx)Z",
            "model_call_id": NSNull(), "tool_call_id": NSNull(),
            "workflow_run_id": NSNull(), "memory_id": NSNull(),
            "artifact_id": NSNull(), "command_id": NSNull(), "effect_id": NSNull(),
        ])
    }
    return try JSONSerialization.data(withJSONObject: ["events": events])
}

// MARK: - Durable tool audit log

@Suite("ActantAuditLog durability")
struct ActantAuditLogTests {

    @Test("append emits append_agent_message with the tool-audit sentinel")
    func appendEmitsSentinel() async throws {
        let session = MockURLProtocol.makeSession()
        let sawSentinel = Flag()
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/command")
            let body = String(data: req.bodyData(), encoding: .utf8) ?? ""
            if body.contains("\"command_type\":\"append_agent_message\""),
               body.contains("_swoosh_tool_audit") {
                sawSentinel.raise()
            }
            if body.contains("create_session") {
                return (200, ["content-type": "application/json"],
                    Data(#"{"command_id":"c_c","event_id":"e_c","result":{"session_id":"_swoosh_tool_audit"}}"#.utf8))
            }
            return (200, ["content-type": "application/json"],
                Data(#"{"command_id":"c_1","result":{}}"#.utf8))
        }) {
            let log = ActantAuditLog(backend: makeBackend(session: session))
            try await log.append(AuditEntry(kind: .toolCallSucceeded, toolName: "file.read", detail: "ok"))
        }
        #expect(sawSentinel.isRaised)
    }

    @Test("tail / getEvent decode audit entries back from the ledger")
    func tailDecodes() async throws {
        let session = MockURLProtocol.makeSession()
        let entries = [
            AuditEntry(id: "a1", kind: .toolCallStarted, toolName: "git.status", detail: "start"),
            AuditEntry(id: "a2", kind: .toolCallSucceeded, toolName: "git.status", detail: "done"),
        ]
        let body = try ledgerEvents(entries, sentinelKey: "_swoosh_tool_audit")
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/events")
            return (200, ["content-type": "application/json"], body)
        }) {
            let log = ActantAuditLog(backend: makeBackend(session: session))
            let tail = await log.tail(limit: 10)
            #expect(tail.count == 2)
            #expect(tail.map(\.id) == ["a1", "a2"])
            #expect(await log.getEvent(id: "a2")?.detail == "done")
            #expect(await log.search(query: "git.status", limit: 10).count == 2)
        }
    }
}

// MARK: - Durable approval store

@Suite("ActantApprovalStore durability")
struct ActantApprovalStoreTests {

    @Test("reduces an append-only log to the latest record per id")
    func reducesToLatest() async throws {
        let session = MockURLProtocol.makeSession()
        let pending = ApprovalRecord(
            id: "ap1", sessionID: "s1", toolName: "file.write",
            risk: .high, permission: .selectedFolderWrite,
            inputPreview: "write README.md", origin: .model
        )
        var resolved = pending
        resolved.status = .denied
        resolved.resolvedAt = Date()
        resolved.resolvedBy = .human
        resolved.denyReason = "not now"

        // The log holds both versions of ap1 plus an untouched pending ap2.
        let pending2 = ApprovalRecord(
            id: "ap2", sessionID: "s1", toolName: "git.commit",
            risk: .medium, permission: .selectedFolderWrite,
            inputPreview: "commit", origin: .model
        )
        let body = try ledgerEvents([pending, resolved, pending2], sentinelKey: "_swoosh_approval")
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/events")
            return (200, ["content-type": "application/json"], body)
        }) {
            let store = ActantApprovalStore(backend: makeBackend(session: session))
            // ap1 resolved to .denied — the later record wins.
            #expect(await store.get(id: "ap1")?.status == .denied)
            #expect(await store.get(id: "ap1")?.denyReason == "not now")
            // Only ap2 remains pending.
            let stillPending = await store.listPending(sessionID: nil)
            #expect(stillPending.map(\.id) == ["ap2"])
        }
    }
}
