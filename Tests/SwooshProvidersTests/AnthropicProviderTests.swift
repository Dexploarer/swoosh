// Tests/SwooshProvidersTests/AnthropicProviderTests.swift — 0.1A
//
// Integration tests (MockHTTPClient — no network) for the Anthropic
// Messages-API provider, the ProviderError quota classifier, the
// LocalizedError surfacing, and codex usage-limit detection. Plus a live
// smoke test gated on ANTHROPIC_API_KEY so the default suite stays
// hermetic but a real happy-path call runs when a key is present.

import Testing
import Foundation
@testable import SwooshProviders
@testable import SwooshSecrets
@testable import SwooshTools
@testable import SwooshModels

// ═══════════════════════════════════════════════════════════════════
// MARK: - Anthropic provider (integration, mocked HTTP)
// ═══════════════════════════════════════════════════════════════════

@Suite("AnthropicProvider")
struct AnthropicProviderTests {

    private func storeWithKey() async -> InMemorySecretStore {
        let store = InMemorySecretStore()
        await store.set("sk-ant-test", ref: SecretRef("anthropic", "api_key"))
        return store
    }

    @Test("Provider identity + capabilities")
    func identity() {
        let provider = AnthropicProvider(secrets: InMemorySecretStore())
        #expect(provider.providerID == ProviderID("anthropic"))
        #expect(provider.capabilities.streaming)
        #expect(provider.capabilities.toolCalling)
    }

    @Test("Missing API key gives clean authMissing error")
    func missingKey() async {
        let provider = AnthropicProvider(secrets: InMemorySecretStore())
        do {
            _ = try await provider.complete(
                ModelRequest(model: ModelDefaults.anthropicModelID,
                             messages: [ChatMessage(role: .user, content: "hi")])
            )
            Issue.record("Should throw")
        } catch ProviderError.authMissing(let id, let msg) {
            #expect(id == ProviderID("anthropic"))
            #expect(msg.contains("swoosh provider auth anthropic"))
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Parses text + usage from a Messages response")
    func parsesResponse() async throws {
        let http = MockHTTPClient()
        await http.enqueueJSON("""
        {
          "id": "msg_1", "type": "message", "role": "assistant",
          "model": "claude-opus-4-7",
          "content": [ { "type": "text", "text": "Hello there!" } ],
          "stop_reason": "end_turn",
          "usage": { "input_tokens": 12, "output_tokens": 3 }
        }
        """)
        let provider = AnthropicProvider(secrets: await storeWithKey(), http: http)
        let resp = try await provider.complete(ModelRequest(
            model: "claude-opus-4-7",
            messages: [
                ChatMessage(role: .system, content: "You are terse."),
                ChatMessage(role: .user, content: "hi"),
            ]
        ))
        #expect(resp.text == "Hello there!")
        #expect(resp.model == "claude-opus-4-7")
        #expect(resp.usage?.promptTokens == 12)
        #expect(resp.usage?.completionTokens == 3)
        #expect(resp.usage?.totalTokens == 15)
    }

    @Test("Parses tool_use content blocks into tool calls")
    func parsesToolUse() async throws {
        let http = MockHTTPClient()
        await http.enqueueJSON("""
        {
          "id": "msg_2", "type": "message", "role": "assistant",
          "model": "claude-opus-4-7",
          "content": [
            { "type": "text", "text": "calling a tool" },
            { "type": "tool_use", "id": "toolu_1", "name": "get_weather",
              "input": { "city": "SF" } }
          ],
          "stop_reason": "tool_use"
        }
        """)
        let provider = AnthropicProvider(secrets: await storeWithKey(), http: http)
        let resp = try await provider.complete(ModelRequest(
            model: "claude-opus-4-7",
            messages: [ChatMessage(role: .user, content: "weather?")]
        ))
        #expect(resp.toolCalls.count == 1)
        #expect(resp.toolCalls.first?.name == "get_weather")
        #expect(resp.finishReason == "tool_use")
    }

    @Test("Request: system extracted, max_tokens set, auth headers present")
    func requestShape() async throws {
        let http = MockHTTPClient()
        await http.enqueueJSON("""
        { "content": [ { "type": "text", "text": "ok" } ], "model": "m" }
        """)
        let provider = AnthropicProvider(secrets: await storeWithKey(), http: http)
        _ = try await provider.complete(ModelRequest(
            model: "claude-opus-4-7",
            messages: [
                ChatMessage(role: .system, content: "be brief"),
                ChatMessage(role: .user, content: "hi"),
                ChatMessage(role: .assistant, content: "hey"),
            ]
        ))
        let recorded = await http.getRecordedRequests()
        let req = try #require(recorded.first)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") != nil)

        let bodyData = try #require(req.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["system"] as? String == "be brief")
        #expect(body["max_tokens"] as? Int != nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        // system was lifted out — only user + assistant remain.
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { ($0["role"] as? String) != "system" })
    }

    @Test("splitSystem lifts system/developer turns out of messages")
    func splitSystem() {
        let (system, messages) = AnthropicProvider.splitSystem([
            ChatMessage(role: .system, content: "sys-a"),
            ChatMessage(role: .developer, content: "sys-b"),
            ChatMessage(role: .user, content: "u1"),
            ChatMessage(role: .assistant, content: "a1"),
        ])
        #expect(system == "sys-a\n\nsys-b")
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[1]["role"] as? String == "assistant")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Quota / rate-limit classification
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderError classification")
struct ProviderErrorClassificationTests {

    @Test("insufficient_quota body → quotaExceeded (even at 429)")
    func quotaFromBody() {
        let e = ProviderError.classifyHTTPFailure(
            providerID: "openai", status: 429,
            body: #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota"}}"#
        )
        guard case .quotaExceeded(let id, let msg, _) = e else {
            Issue.record("Expected quotaExceeded, got \(e)"); return
        }
        #expect(id == ProviderID("openai"))
        #expect(msg.lowercased().contains("quota"))
    }

    @Test("Plain 429 → rateLimited with Retry-After parsed")
    func rateLimited() {
        let e = ProviderError.classifyHTTPFailure(
            providerID: "openai", status: 429,
            body: #"{"error":{"message":"Too many requests"}}"#,
            retryAfterHeader: "30"
        )
        guard case .rateLimited(_, let retry) = e else {
            Issue.record("Expected rateLimited, got \(e)"); return
        }
        #expect(retry == 30)
    }

    @Test("401 → authMissing")
    func auth() {
        let e = ProviderError.classifyHTTPFailure(providerID: "openai", status: 401, body: "nope")
        guard case .authMissing = e else { Issue.record("Expected authMissing, got \(e)"); return }
    }

    @Test("500 → requestFailed")
    func generic() {
        let e = ProviderError.classifyHTTPFailure(providerID: "openai", status: 500, body: "boom")
        guard case .requestFailed = e else { Issue.record("Expected requestFailed, got \(e)"); return }
    }

    @Test("allRoutesFailed errorDescription folds in inner reasons")
    func allRoutesFolds() {
        let inner = ProviderError.quotaExceeded("codex", message: "hit your usage limit", resetsAt: nil)
        let attempt = ProviderAttemptError(
            route: ProviderRoute(role: .primaryChat, providerID: "codex", model: "auto"),
            error: inner
        )
        let agg = ProviderError.allRoutesFailed([attempt])
        let desc = agg.errorDescription ?? ""
        #expect(desc.contains("usage limit"))
        #expect(desc.contains("codex"))
        // No longer the opaque "error 7".
        #expect(!desc.contains("error 7"))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Codex usage-limit detection
// ═══════════════════════════════════════════════════════════════════

@Suite("Codex usage-limit detection")
struct CodexUsageLimitTests {

    @Test("Detects + strips ERROR: prefix from a usage-limit line")
    func detects() {
        let out = "session id: x\nERROR: You've hit your usage limit. Try again at May 31st.\ndone"
        let line = CodexBridgeProvider.usageLimitLine(in: out)
        #expect(line?.lowercased().contains("usage limit") == true)
        #expect(line?.hasPrefix("ERROR:") == false)
    }

    @Test("Returns nil when no usage-limit marker present")
    func none() {
        #expect(CodexBridgeProvider.usageLimitLine(in: "all good\nPING") == nil)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Live smoke test (gated on ANTHROPIC_API_KEY)
// ═══════════════════════════════════════════════════════════════════

@Suite("AnthropicProvider live smoke")
struct AnthropicProviderSmokeTests {

    @Test("Real Messages call returns non-empty text")
    func liveHappyPath() async throws {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else {
            // No key in this environment — smoke test is a no-op (passes).
            return
        }
        let store = InMemorySecretStore()
        await store.set(key, ref: SecretRef("anthropic", "api_key"))
        let provider = AnthropicProvider(secrets: store)
        let resp = try await provider.complete(ModelRequest(
            model: ModelDefaults.anthropicFastModelID,
            messages: [ChatMessage(role: .user, content: "Reply with the single word PONG.")],
            maxOutputTokens: 16
        ))
        #expect(!resp.text.isEmpty)
    }
}
