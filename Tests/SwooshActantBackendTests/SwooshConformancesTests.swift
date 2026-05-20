// SwooshConformancesTests.swift — Round-trip the conformance extensions.

import Foundation
import Testing
@testable import SwooshActantBackend
import ActantDB
import ActantAgent
import SwooshCore

// MARK: - Helpers

private func backend(session: URLSession) -> AgentBackend {
    AgentBackend(
        client: ActantClient(baseURL: URL(string: "http://local-diagnostic")!, urlSession: session),
        workspaceID: "ws_test", actorID: "act_test"
    )
}

private final class CommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func observe(_ request: URLRequest) -> (index: Int, body: String) {
        lock.withLock {
            let index = count
            count += 1
            return (index, String(data: request.bodyData(), encoding: .utf8) ?? "")
        }
    }
}

/// Build a `/v1/events` response body with full AgentEvent fields. Each
/// entry's `payload_inline` is the JSON-serialized payload object.
private func eventsResponse(_ entries: [(eventType: String, payload: [String: Any])]) throws -> Data {
    let events: [[String: Any]] = entries.enumerated().map { idx, entry in
        let payloadData = try? JSONSerialization.data(withJSONObject: entry.payload, options: [])
        let payloadStr = payloadData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [
            "id": "evt_\(idx)",
            "workspace_id": "ws_test", "actor_id": "act_test", "session_id": "s_1",
            "parent_event_id": NSNull(), "event_type": entry.eventType,
            "causality_kind": "observation", "sensitivity": "low",
            "authority_scope_id": NSNull(),
            "payload_inline": payloadStr, "payload_ref": NSNull(),
            "payload_hash": "h\(idx)", "event_hash": "eh\(idx)",
            "created_at": "2026-05-18T12:00:0\(idx)Z",
            "model_call_id": NSNull(), "tool_call_id": NSNull(),
            "workflow_run_id": NSNull(), "memory_id": NSNull(),
            "artifact_id": NSNull(), "command_id": NSNull(), "effect_id": NSNull(),
        ]
    }
    return try JSONSerialization.data(withJSONObject: ["events": events], options: [])
}

// MARK: - Session

@Suite("SwooshSessionStore conformance")
struct SwooshSessionStoreTests {

    @Test(".user message dispatches append_user_message")
    func userAppendsViaCommand() async throws {
        let session = MockURLProtocol.makeSession()
        let recorder = CommandRecorder()
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/command")
            let (index, body) = recorder.observe(req)
            if index == 0 {
                #expect(body.contains("\"command_type\":\"create_session\""))
                #expect(body.contains("\"session_id\":\"s_1\""))
                return (200, ["content-type": "application/json"],
                    Data(#"{"command_id":"c_create","event_id":"e_create","result":{"session_id":"s_1"}}"#.utf8))
            }
            #expect(index == 1)
            #expect(body.contains("\"command_type\":\"append_user_message\""))
            #expect(body.contains("\"text\":\"hello\""))
            return (200, ["content-type": "application/json"],
                Data(#"{"command_id":"c_1","result":{}}"#.utf8))
        }) {
            let store = SwooshSessionStore(backend: backend(session: session))
            try await store.appendMessage(
                sessionID: "s_1",
                message: ChatMessage(role: .user, content: "hello")
            )
        }
    }

    @Test(".assistant routes through append_agent_message")
    func assistantAppendsViaCommand() async throws {
        let session = MockURLProtocol.makeSession()
        let recorder = CommandRecorder()
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/command")
            let (index, body) = recorder.observe(req)
            if index == 0 {
                #expect(body.contains("\"command_type\":\"create_session\""))
                #expect(body.contains("\"session_id\":\"s_1\""))
                return (200, ["content-type": "application/json"],
                    Data(#"{"command_id":"c_create","event_id":"e_create","result":{"session_id":"s_1"}}"#.utf8))
            }
            #expect(index == 1)
            #expect(body.contains("\"command_type\":\"append_agent_message\""))
            return (200, ["content-type": "application/json"],
                Data(#"{"command_id":"c_2","result":{}}"#.utf8))
        }) {
            let store = SwooshSessionStore(backend: backend(session: session))
            try await store.appendMessage(
                sessionID: "s_1",
                message: ChatMessage(role: .assistant, content: "hi back")
            )
        }
    }

    @Test("loadTranscript decodes events back to ChatMessage[]")
    func loadTranscriptRoundTrips() async throws {
        let session = MockURLProtocol.makeSession()
        let body = try eventsResponse([
            (eventType: "user_message_received",
             payload: ["message_id": "m1", "text": "hello"]),
            (eventType: "agent_message",
             payload: ["message_id": "m2", "text": "world"]),
        ])
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/events")
            return (200, ["content-type": "application/json"], body)
        }) {
            let store = SwooshSessionStore(backend: backend(session: session))
            let messages = try await store.loadTranscript(sessionID: "s_1")
            #expect(messages.count == 2)
            #expect(messages[0].role == .user)
            #expect(messages[0].content == "hello")
            #expect(messages[1].role == .assistant)
            #expect(messages[1].content == "world")
        }
    }
}

// MARK: - Auditor

@Suite("SwooshResponseAuditor conformance")
struct SwooshResponseAuditorTests {

    @Test("logResponseAudit emits append_agent_message with sentinel envelope")
    func logEmitsSentinel() async throws {
        let session = MockURLProtocol.makeSession()
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/command")
            let body = String(data: req.bodyData(), encoding: .utf8) ?? ""
            #expect(body.contains("\"command_type\":\"append_agent_message\""))
            #expect(body.contains("_swoosh_audit"))
            return (200, ["content-type": "application/json"],
                Data(#"{"command_id":"c_3","result":{}}"#.utf8))
        }) {
            let auditor = SwooshResponseAuditor(backend: backend(session: session))
            let record = ResponseAuditRecord(
                sessionID: "s_1", modelUsed: "gpt-4o",
                memoryIDsUsed: ["m_1"], setupReportUsed: true,
                permissionSummaryUsed: true
            )
            try await auditor.logResponseAudit(record)
        }
    }

    @Test("lastResponseAudit reverse-scans events for the sentinel")
    func lastReverseScans() async throws {
        let session = MockURLProtocol.makeSession()

        // Encode an actual ResponseAuditRecord so the Date encoding strategy
        // matches what Auditor.last expects when it decodes back.
        let originalRecord = ResponseAuditRecord(
            sessionID: "s_1", responseID: "r_1",
            modelUsed: "gpt-4o", memoryIDsUsed: ["m_1"],
            setupReportUsed: true, permissionSummaryUsed: true
        )
        let recordData = try JSONEncoder().encode(originalRecord)
        let recordValue = try JSONSerialization.jsonObject(with: recordData)

        let envelopeObj: [String: Any] = [
            "_swoosh_audit": ["v": 1, "r": recordValue],
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelopeObj, options: [])
        let envelopeStr = String(data: envelopeData, encoding: .utf8) ?? "{}"

        let body = try eventsResponse([
            (eventType: "agent_message",
             payload: ["message_id": "m1", "text": envelopeStr]),
        ])

        try await MockURLProtocol.with({ _ in
            return (200, ["content-type": "application/json"], body)
        }) {
            let auditor = SwooshResponseAuditor(backend: backend(session: session))
            let record = try await auditor.lastResponseAudit(sessionID: "s_1")
            #expect(record != nil)
            #expect(record?.modelUsed == "gpt-4o")
            #expect(record?.memoryIDsUsed == ["m_1"])
            #expect(record?.responseID == "r_1")
        }
    }
}

// MARK: - MemoryStore conformance

@Suite("MemoryStore SwooshCore conformance")
struct MemoryStoreConformanceTests {

    @Test("loadApprovedMemories projects rows to (id, text, category)")
    func loadApprovedMemoriesMaps() async throws {
        let session = MockURLProtocol.makeSession()
        try await MockURLProtocol.with({ req in
            #expect(req.url?.path == "/v1/memories")
            let json = #"""
                {"memories":[
                    {"status":"approved","id":"m_1","workspace_id":"ws_test",
                     "text":"User is a Swift developer","category":"profile",
                     "sensitivity":"low","created_at":"2026-05-18T12:00:00Z"}
                ]}
                """#
            return (200, ["content-type": "application/json"], Data(json.utf8))
        }) {
            let store = MemoryStore(backend: backend(session: session))
            let memories: [(id: String, text: String, category: String)] =
                try await store.loadApprovedMemories()
            #expect(memories.count == 1)
            #expect(memories[0].id == "m_1")
            #expect(memories[0].text == "User is a Swift developer")
            #expect(memories[0].category == "profile")
        }
    }
}
