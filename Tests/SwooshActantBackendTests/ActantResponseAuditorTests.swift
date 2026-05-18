import Foundation
import Testing
import ActantDB
import SwooshCore
@testable import SwooshActantBackend

@Suite("ActantResponseAuditor")
struct ActantResponseAuditorTests {

    private func backend() -> ActantBackendConfig {
        ActantBackendConfig(
            client: ActantClient(
                baseURL: URL(string: "http://127.0.0.1:4555")!,
                urlSession: MockURLProtocol.makeSession()
            ),
            workspaceID: "ws_test",
            actorID: "act_test"
        )
    }

    @Test("logResponseAudit emits append_agent_message with JSON sentinel in text")
    func logEmitsSentinel() async throws {
        try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["command_type"] as? String == "append_agent_message")
            let input = body["input"] as! [String: Any]
            let text = input["text"] as! String
            // Parse the sentinel JSON.
            let payload = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            #expect(payload["_swoosh_audit"] as? Bool == true)
            #expect(payload["session_id"] as? String == "sess_x")
            #expect(payload["model_used"] as? String == "claude-opus")
            let mems = payload["memory_ids_used"] as! [String]
            #expect(mems == ["mem_1", "mem_2"])
            #expect(payload["cookies_excluded"] as? Bool == true)
            let resp = #"{"command_id":"cmd_1","event_id":"evt_1","result":{}}"#
            return (200, [:], Data(resp.utf8))
        }) {
            let auditor = ActantResponseAuditor(backend())
            let record = ResponseAuditRecord(
                sessionID: "sess_x",
                modelUsed: "claude-opus",
                memoryIDsUsed: ["mem_1", "mem_2"],
                setupReportUsed: true,
                permissionSummaryUsed: true
            )
            try await auditor.logResponseAudit(record)
        }
    }

    @Test("lastResponseAudit reverse-scans events for the audit sentinel and round-trips")
    func lastResponseAuditRoundTrip() async throws {
        // First call: write the record. Capture the encoded text for the
        // second call (loadTranscript) which returns it back.
        actor TextHolder { var text = ""; func set(_ s: String) { text = s }; func get() -> String { text } }
        let holder = TextHolder()

        try await MockURLProtocol.with({ request in
            // First request: command (write). Second request: events (read).
            if request.url?.path == "/v1/command" {
                let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
                let input = body["input"] as! [String: Any]
                let text = input["text"] as! String
                Task { await holder.set(text) }
                return (200, [:], #"{"command_id":"cmd_1","event_id":"evt_1","result":{}}"#.data(using: .utf8)!)
            }
            // /v1/events
            // We don't have a way to read holder.text synchronously here, so
            // bounce via a sleep in the handler is not ideal. Instead, the
            // test below uses two sequential `with` blocks so each handler
            // can be focused. Fall through here to avoid relying on it.
            return (500, [:], Data())
        }) {
            let auditor = ActantResponseAuditor(backend())
            try await auditor.logResponseAudit(ResponseAuditRecord(
                sessionID: "sess_x",
                modelUsed: "m",
                memoryIDsUsed: ["a"],
                setupReportUsed: true,
                permissionSummaryUsed: true
            ))
        }

        let savedText = await holder.get()
        #expect(!savedText.isEmpty, "first call should have captured the sentinel text")

        // Second mock: serve an events response containing the sentinel.
        // Build the JSON via JSONSerialization to avoid double-escape hazards.
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/v1/events")
            let payloadJSON = try! String(
                data: JSONSerialization.data(withJSONObject: ["text": savedText]),
                encoding: .utf8
            )!
            let response: [String: Any] = [
                "events": [[
                    "id": "evt_1",
                    "workspace_id": "ws_test",
                    "actor_id": "act_test",
                    "session_id": "sess_x",
                    "parent_event_id": NSNull(),
                    "event_type": "agent_message_appended",
                    "causality_kind": "effect",
                    "sensitivity": "low",
                    "authority_scope_id": NSNull(),
                    "payload_inline": payloadJSON,
                    "payload_ref": NSNull(),
                    "payload_hash": "h",
                    "event_hash": "eh",
                    "created_at": "2026-05-18T12:00:00Z",
                    "model_call_id": NSNull(),
                    "tool_call_id": NSNull(),
                    "workflow_run_id": NSNull(),
                    "memory_id": NSNull(),
                    "artifact_id": NSNull(),
                    "command_id": NSNull(),
                    "effect_id": NSNull(),
                ]]
            ]
            let data = try! JSONSerialization.data(withJSONObject: response)
            return (200, [:], data)
        }) {
            let auditor = ActantResponseAuditor(backend())
            let last = try await auditor.lastResponseAudit(sessionID: "sess_x")
            #expect(last != nil)
            #expect(last?.modelUsed == "m")
            #expect(last?.memoryIDsUsed == ["a"])
            #expect(last?.cookiesExcluded == true)
        }
    }

    @Test("lastResponseAudit returns nil when no sentinel is present")
    func lastResponseAuditEmpty() async throws {
        try await MockURLProtocol.with({ _ in
            let resp = """
            {"events":[{
              "id":"evt_1","workspace_id":"ws_test","actor_id":"act_test",
              "session_id":"sess_x","parent_event_id":null,
              "event_type":"agent_message_appended","causality_kind":"effect",
              "sensitivity":"low","authority_scope_id":null,
              "payload_inline":"{\\"text\\":\\"a normal message\\"}","payload_ref":null,
              "payload_hash":"h","event_hash":"eh","created_at":"2026-05-18T12:00:00Z",
              "model_call_id":null,"tool_call_id":null,"workflow_run_id":null,
              "memory_id":null,"artifact_id":null,"command_id":null,"effect_id":null
            }]}
            """
            return (200, [:], Data(resp.utf8))
        }) {
            let auditor = ActantResponseAuditor(backend())
            let last = try await auditor.lastResponseAudit(sessionID: "sess_x")
            #expect(last == nil)
        }
    }
}
