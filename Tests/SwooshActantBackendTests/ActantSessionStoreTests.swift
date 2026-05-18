import Foundation
import Testing
import ActantDB
import SwooshCore
@testable import SwooshActantBackend

@Suite("ActantSessionStore")
struct ActantSessionStoreTests {

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

    @Test(".user message dispatches append_user_message with the right input shape")
    func userMessage() async throws {
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/v1/command")
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["command_type"] as? String == "append_user_message")
            #expect(body["workspace_id"] as? String == "ws_test")
            #expect(body["actor_id"] as? String == "act_test")
            let input = body["input"] as! [String: Any]
            #expect(input["session_id"] as? String == "sess_1")
            #expect(input["text"] as? String == "hello")
            let resp = #"{"command_id":"cmd_1","event_id":"evt_1","result":{}}"#
            return (200, [:], Data(resp.utf8))
        }) {
            let store = ActantSessionStore(backend())
            try await store.appendMessage(
                sessionID: "sess_1",
                message: ChatMessage(role: .user, content: "hello")
            )
        }
    }

    @Test(".assistant message dispatches append_agent_message")
    func assistantMessage() async throws {
        try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["command_type"] as? String == "append_agent_message")
            let resp = #"{"command_id":"cmd_2","event_id":"evt_2","result":{}}"#
            return (200, [:], Data(resp.utf8))
        }) {
            let store = ActantSessionStore(backend())
            try await store.appendMessage(
                sessionID: "sess_1",
                message: ChatMessage(role: .assistant, content: "hi")
            )
        }
    }

    @Test(".system message is silently dropped (PromptBuilder owns it)")
    func systemMessageNoOp() async throws {
        // If the store accidentally dispatches, the mock will record an
        // expectation failure. We assert zero requests by setting an
        // unconditional Issue.record on entry — if no request fires, the
        // body completes without it.
        actor Counter { var n = 0; func bump() { n += 1 } }
        let counter = Counter()
        try await MockURLProtocol.with({ _ in
            Task { await counter.bump() }
            return (500, [:], Data())  // would fail loudly if reached
        }) {
            let store = ActantSessionStore(backend())
            try await store.appendMessage(
                sessionID: "sess_1",
                message: ChatMessage(role: .system, content: "system prompt")
            )
        }
        let n = await counter.n
        #expect(n == 0, "system messages must not hit the wire")
    }

    @Test(".tool message dispatches append_agent_message with [tool] prefix")
    func toolMessage() async throws {
        try await MockURLProtocol.with({ request in
            let body = try! JSONSerialization.jsonObject(with: request.bodyData()) as! [String: Any]
            #expect(body["command_type"] as? String == "append_agent_message")
            let input = body["input"] as! [String: Any]
            #expect((input["text"] as? String)?.hasPrefix("[tool] ") == true)
            let resp = #"{"command_id":"cmd_3","event_id":"evt_3","result":{}}"#
            return (200, [:], Data(resp.utf8))
        }) {
            let store = ActantSessionStore(backend())
            try await store.appendMessage(
                sessionID: "sess_1",
                message: ChatMessage(role: .tool, content: "result body")
            )
        }
    }

    @Test("loadTranscript decodes user_message + agent_message events back to ChatMessage[]")
    func loadTranscript() async throws {
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/v1/events")
            let resp = """
            {"events":[
              {
                "id":"evt_1","workspace_id":"ws_test","actor_id":"act_test",
                "session_id":"sess_1","parent_event_id":null,
                "event_type":"user_message_received","causality_kind":"observation",
                "sensitivity":"low","authority_scope_id":null,
                "payload_inline":"{\\"text\\":\\"hello\\"}","payload_ref":null,
                "payload_hash":"h","event_hash":"eh","created_at":"2026-05-18T12:00:00Z",
                "model_call_id":null,"tool_call_id":null,"workflow_run_id":null,
                "memory_id":null,"artifact_id":null,"command_id":null,"effect_id":null
              },
              {
                "id":"evt_2","workspace_id":"ws_test","actor_id":"act_test",
                "session_id":"sess_1","parent_event_id":null,
                "event_type":"agent_message_appended","causality_kind":"effect",
                "sensitivity":"low","authority_scope_id":null,
                "payload_inline":"{\\"text\\":\\"hi back\\"}","payload_ref":null,
                "payload_hash":"h","event_hash":"eh","created_at":"2026-05-18T12:00:01Z",
                "model_call_id":null,"tool_call_id":null,"workflow_run_id":null,
                "memory_id":null,"artifact_id":null,"command_id":null,"effect_id":null
              },
              {
                "id":"evt_3","workspace_id":"ws_test","actor_id":"act_test",
                "session_id":"sess_1","parent_event_id":null,
                "event_type":"tool_call_requested","causality_kind":"intent",
                "sensitivity":"medium","authority_scope_id":null,
                "payload_inline":null,"payload_ref":null,
                "payload_hash":"h","event_hash":"eh","created_at":"2026-05-18T12:00:02Z",
                "model_call_id":null,"tool_call_id":"tc_1","workflow_run_id":null,
                "memory_id":null,"artifact_id":null,"command_id":null,"effect_id":null
              }
            ]}
            """
            return (200, [:], Data(resp.utf8))
        }) {
            let store = ActantSessionStore(backend())
            let messages = try await store.loadTranscript(sessionID: "sess_1")
            #expect(messages.count == 2, "tool_call_requested events should be skipped")
            #expect(messages[0].role == .user)
            #expect(messages[0].content == "hello")
            #expect(messages[1].role == .assistant)
            #expect(messages[1].content == "hi back")
        }
    }

    @Test("[tool] prefix in agent_message_appended decodes back to .tool role")
    func loadTranscriptToolPrefix() async throws {
        try await MockURLProtocol.with({ _ in
            let resp = """
            {"events":[{
              "id":"evt_1","workspace_id":"ws_test","actor_id":"act_test",
              "session_id":"sess_1","parent_event_id":null,
              "event_type":"agent_message_appended","causality_kind":"effect",
              "sensitivity":"low","authority_scope_id":null,
              "payload_inline":"{\\"text\\":\\"[tool] result body\\"}","payload_ref":null,
              "payload_hash":"h","event_hash":"eh","created_at":"2026-05-18T12:00:00Z",
              "model_call_id":null,"tool_call_id":null,"workflow_run_id":null,
              "memory_id":null,"artifact_id":null,"command_id":null,"effect_id":null
            }]}
            """
            return (200, [:], Data(resp.utf8))
        }) {
            let store = ActantSessionStore(backend())
            let m = try await store.loadTranscript(sessionID: "sess_1")
            #expect(m.count == 1)
            #expect(m[0].role == .tool)
            #expect(m[0].content == "result body")
        }
    }
}
