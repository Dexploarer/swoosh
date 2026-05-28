// Tests/SwooshProvidersTests/DevProxyProviderTests.swift — 0.1A
//
// The dev proxy reuses LocalOpenAICompatibleProvider under its own
// providerID + a Bearer key. These tests pin the two things that matter:
//   • requests target the configured localhost:3001/v1 base URL, and
//   • the API key is sent as `Authorization: Bearer …` (only when set —
//     the default no-key local provider must stay header-free).
// All mocked — no network.

import Testing
import Foundation
@testable import SwooshProviders
@testable import SwooshTools
@testable import SwooshModels

@Suite("Dev proxy provider")
struct DevProxyProviderTests {

    @Test("Targets the dev-proxy base URL with its own providerID")
    func baseURLAndID() async throws {
        let http = MockHTTPClient()
        await http.enqueueJSON("""
        { "choices": [ { "message": { "content": "PROXY-OK" } } ], "model": "gpt-4o" }
        """)
        let provider = LocalOpenAICompatibleProvider(
            http: http,
            baseURL: ModelDefaults.devProxyBaseURL,
            providerID: ProviderID(ModelDefaults.devProxyProviderID),
            displayName: "Dev Proxy (free tiers)",
            apiKey: "freellmapi-secret"
        )
        #expect(provider.providerID == ProviderID("dev-proxy"))

        let resp = try await provider.complete(ModelRequest(
            model: "auto",
            messages: [ChatMessage(role: .user, content: "hi")]
        ))
        #expect(resp.text == "PROXY-OK")

        let recorded = await http.getRecordedRequests()
        let req = try #require(recorded.first)
        #expect(req.url?.absoluteString == "http://localhost:3001/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer freellmapi-secret")
    }

    @Test("No key configured → no Authorization header (default local behavior)")
    func noKeyNoAuthHeader() async throws {
        let http = MockHTTPClient()
        await http.enqueueJSON("""
        { "choices": [ { "message": { "content": "ok" } } ], "model": "m" }
        """)
        let provider = LocalOpenAICompatibleProvider(
            http: http,
            baseURL: "http://127.0.0.1:11434/v1"
        )
        #expect(provider.providerID == ProviderID("local-openai"))
        _ = try await provider.complete(ModelRequest(
            model: "qwen3:4b",
            messages: [ChatMessage(role: .user, content: "hi")]
        ))
        let recorded = await http.getRecordedRequests()
        let req = try #require(recorded.first)
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Profile + defaults wire the proxy endpoint")
    func profileDefaults() {
        #expect(ModelDefaults.devProxyBaseURL == "http://localhost:3001/v1")
        #expect(ProviderProfile.devProxy.id == ProviderID("dev-proxy"))
        #expect(ProviderProfile.devProxy.baseURL == "http://localhost:3001/v1")
        if case .apiKey(let ns, let key) = ProviderProfile.devProxy.auth {
            #expect(ns == "dev-proxy")
            #expect(key == "api_key")
        } else {
            Issue.record("dev-proxy should use apiKey auth")
        }
    }
}
