// SwooshProviders/OpenRouterProvider.swift — 0.9P OpenRouter Chat Completions + PKCE
//
// Real HTTP calls to openrouter.ai/api/v1/chat/completions.
// Supports both direct API key and PKCE user-key flow.
// PKCE uses real CryptoKit S256.

import Foundation
import SwooshSecrets
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - OpenRouter Provider
// ═══════════════════════════════════════════════════════════════════

public actor OpenRouterProvider: StreamingModelProviding {
    public nonisolated let providerID: ProviderID = "openrouter"
    public nonisolated let displayName: String = "OpenRouter"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: true, toolCalling: true, structuredOutput: false,
        embeddings: false, vision: true
    )

    private let secrets: any SecretStoring
    private let http: any HTTPClient
    private let baseURL: String

    public init(secrets: any SecretStoring, http: any HTTPClient = URLSessionHTTPClient(),
                baseURL: String = "https://openrouter.ai/api/v1") {
        self.secrets = secrets; self.http = http; self.baseURL = baseURL
    }

    // ── Complete ──────────────────────────────────────────────────

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        let apiKey = try await loadAPIKey()
        let httpReq = try buildRequest(apiKey: apiKey, modelReq: request, stream: false)
        let response = try await http.send(httpReq)
        return try parseResponse(response.data, model: request.model)
    }

    // ── Stream ────────────────────────────────────────────────────

    public func stream(_ request: ModelRequest) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        let apiKey = try await loadAPIKey()
        let httpReq = try buildRequest(apiKey: apiKey, modelReq: request, stream: true)
        let (_, dataStream) = try await http.sendStreaming(httpReq)

        return AsyncThrowingStream { continuation in
            Task {
                var accumulated = ""
                var toolCalls: [ProviderToolCall] = []
                do {
                    for try await chunk in dataStream {
                        guard let line = String(data: chunk, encoding: .utf8),
                              line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        if json == "[DONE]" { break }
                        if let event = self.parseChatCompletionsStreamChunk(json) {
                            switch event {
                            case .textDelta(let t): accumulated += t; continuation.yield(event)
                            case .toolCallDelta(let tc): toolCalls.append(tc); continuation.yield(event)
                            default: continuation.yield(event)
                            }
                        }
                    }
                    let final = ModelResponse(
                        providerID: self.providerID, model: request.model,
                        text: accumulated, toolCalls: toolCalls, finishReason: "stop"
                    )
                    continuation.yield(.done(final))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // ── Internals ─────────────────────────────────────────────────

    private func loadAPIKey() async throws -> String {
        do {
            return try await secrets.get(SecretRef("openrouter", "api_key"))
        } catch {
            throw ProviderError.authMissing(providerID,
                "OpenRouter API key not found. Run: swoosh provider auth openrouter --api-key (or --pkce)")
        }
    }

    private func buildRequest(apiKey: String, modelReq: ModelRequest, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw ProviderError.requestFailed(providerID, "Invalid base URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://swoosh.ai", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Swoosh", forHTTPHeaderField: "X-Title")

        var body: [String: Any] = [
            "model": modelReq.model,
            "messages": modelReq.messages.map { msg -> [String: Any] in
                var m: [String: Any] = ["role": msg.role.rawValue, "content": msg.content]
                if let id = msg.toolCallID { m["tool_call_id"] = id }
                return m
            }
        ]
        if stream { body["stream"] = true }
        if let temp = modelReq.temperature { body["temperature"] = temp }
        if let max = modelReq.maxOutputTokens { body["max_tokens"] = max }

        if !modelReq.tools.isEmpty {
            body["tools"] = modelReq.tools.map { tool -> [String: Any] in
                ["type": "function", "function": [
                    "name": tool.name, "description": tool.description,
                    "parameters": tool.inputSchema.toAnyForJSON()
                ] as [String: Any]]
            }
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func parseResponse(_ data: Data, model: String) throws -> ModelResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.responseParseFailed(providerID, "Invalid JSON")
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ProviderError.requestFailed(providerID, message)
        }

        var text = ""
        var toolCalls: [ProviderToolCall] = []

        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any] {
            text = (message["content"] as? String) ?? ""

            if let tcs = message["tool_calls"] as? [[String: Any]] {
                for tc in tcs {
                    if let fn = tc["function"] as? [String: Any] {
                        toolCalls.append(ProviderToolCall(
                            id: (tc["id"] as? String) ?? UUID().uuidString,
                            name: (fn["name"] as? String) ?? "",
                            arguments: .string((fn["arguments"] as? String) ?? "{}")
                        ))
                    }
                }
            }
        }

        var usage: ProviderUsage?
        if let u = json["usage"] as? [String: Any] {
            usage = ProviderUsage(
                promptTokens: (u["prompt_tokens"] as? Int) ?? 0,
                completionTokens: (u["completion_tokens"] as? Int) ?? 0,
                totalTokens: (u["total_tokens"] as? Int) ?? 0
            )
        }

        let responseModel = (json["model"] as? String) ?? model
        return ModelResponse(
            providerID: providerID, model: responseModel, text: text,
            toolCalls: toolCalls, finishReason: "stop", usage: usage
        )
    }

    private func parseChatCompletionsStreamChunk(_ json: String) -> ModelStreamEvent? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let choices = parsed["choices"] as? [[String: Any]],
           let first = choices.first,
           let delta = first["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                return .textDelta(content)
            }
            if let tcs = delta["tool_calls"] as? [[String: Any]], let tc = tcs.first,
               let fn = tc["function"] as? [String: Any] {
                return .toolCallDelta(ProviderToolCall(
                    id: (tc["id"] as? String) ?? UUID().uuidString,
                    name: (fn["name"] as? String) ?? "",
                    arguments: .string((fn["arguments"] as? String) ?? "{}")
                ))
            }
        }

        return nil
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - OpenRouter PKCE Auth Flow
// ═══════════════════════════════════════════════════════════════════

public actor OpenRouterPKCEAuth {
    private let secrets: any SecretStoring
    private let http: any HTTPClient
    private var pendingVerifier: String?

    public init(secrets: any SecretStoring, http: any HTTPClient = URLSessionHTTPClient()) {
        self.secrets = secrets; self.http = http
    }

    /// Build the /auth URL the user should open in their browser.
    public func buildAuthURL(callbackURL: String = "swoosh://openrouter/callback") -> (url: String, verifier: String) {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challengeS256(verifier: verifier)
        self.pendingVerifier = verifier

        let url = "https://openrouter.ai/auth"
            + "?callback_url=\(callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callbackURL)"
            + "&code_challenge=\(challenge)"
            + "&code_challenge_method=S256"

        return (url: url, verifier: verifier)
    }

    /// Exchange the authorization code for a user-controlled API key.
    /// Stores the key in Keychain. Never returns the raw key outside this call.
    public func exchangeCode(_ code: String) async throws -> ProviderHealth {
        guard let verifier = pendingVerifier else {
            throw ProviderError.requestFailed(ProviderID("openrouter"), "No pending PKCE verifier")
        }

        let body: [String: Any] = [
            "code": code,
            "code_challenge_method": "S256",
            "code_verifier": verifier,
        ]

        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response = try await http.send(req)
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let key = json["key"] as? String else {
            throw ProviderError.responseParseFailed(ProviderID("openrouter"), "No key in response")
        }

        // Store in Keychain — never log
        try await secrets.set(key, ref: SecretRef("openrouter", "api_key"))
        self.pendingVerifier = nil

        return ProviderHealth(providerID: ProviderID("openrouter"), status: .healthy,
                              message: "API key obtained via PKCE and stored in Keychain")
    }

    /// Exchange with a manual code (for CLI copy-paste flow)
    public func exchangeManualCode(_ code: String, verifier: String) async throws -> ProviderHealth {
        self.pendingVerifier = verifier
        return try await exchangeCode(code)
    }
}
