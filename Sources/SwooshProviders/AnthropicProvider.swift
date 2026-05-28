// SwooshProviders/AnthropicProvider.swift — 0.1A Anthropic Messages API provider
//
// Real HTTP calls to api.anthropic.com/v1/messages. Bearer auth uses the
// `x-api-key` header (not Authorization) plus the required
// `anthropic-version` header. Key comes from Keychain (anthropic.api_key).
//
// Messages-API specifics handled here:
//   • `max_tokens` is REQUIRED — defaults to 4096 when the caller omits it.
//   • system/developer messages are NOT allowed in the messages array —
//     they are extracted and joined into the top-level `system` field.
//   • response `content` is an array of typed blocks (text / tool_use).
//
// HTTP failures are reclassified through ProviderError.classifyHTTPFailure
// so a plan-quota cap surfaces as .quotaExceeded, not an opaque 500.

import Foundation
import SwooshSecrets
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Anthropic provider
// ═══════════════════════════════════════════════════════════════════

public actor AnthropicProvider: StreamingModelProviding {
    public nonisolated let providerID: ProviderID = "anthropic"
    public nonisolated let displayName: String = "Anthropic (Claude)"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: true, toolCalling: true, structuredOutput: false,
        embeddings: false, vision: true
    )

    /// Default when a request omits `maxOutputTokens` (Anthropic requires it).
    private static let defaultMaxTokens = 4096
    /// Anthropic API version pin. See docs.anthropic.com/en/api/versioning.
    private static let apiVersion = "2023-06-01"

    private let secrets: any SecretStoring
    private let http: any HTTPClient
    private let baseURL: String

    public init(secrets: any SecretStoring,
                http: any HTTPClient = URLSessionHTTPClient(purpose: "provider:anthropic"),
                baseURL: String = "https://api.anthropic.com") {
        self.secrets = secrets; self.http = http; self.baseURL = baseURL
    }

    // ── Complete ──────────────────────────────────────────────────

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        let apiKey = try await loadAPIKey()
        let httpReq = try buildRequest(apiKey: apiKey, modelReq: request, stream: false)
        let response: HTTPResponse
        do {
            response = try await http.send(httpReq)
        } catch let HTTPError.requestFailed(status, body) {
            throw ProviderError.classifyHTTPFailure(providerID: providerID, status: status, body: body)
        }
        return try parseResponse(response.data, model: request.model)
    }

    // ── Stream ────────────────────────────────────────────────────

    public func stream(_ request: ModelRequest) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        let apiKey = try await loadAPIKey()
        let httpReq = try buildRequest(apiKey: apiKey, modelReq: request, stream: true)
        let (_, dataStream) = try await http.sendStreaming(httpReq)
        let pid = providerID
        let model = request.model

        return AsyncThrowingStream { continuation in
            Task {
                var accumulated = ""
                do {
                    for try await chunk in dataStream {
                        guard let line = String(data: chunk, encoding: .utf8),
                              line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        if let text = Self.parseStreamTextDelta(json) {
                            accumulated += text
                            continuation.yield(.textDelta(text))
                        }
                    }
                    continuation.yield(.done(ModelResponse(
                        providerID: pid, model: model, text: accumulated,
                        toolCalls: [], finishReason: "stop"
                    )))
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
            return try await secrets.get(SecretRef("anthropic", "api_key"))
        } catch {
            throw ProviderError.authMissing(providerID,
                "Anthropic API key not found. Run: swoosh provider auth anthropic --api-key")
        }
    }

    func buildRequest(apiKey: String, modelReq: ModelRequest, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw ProviderError.requestFailed(providerID, "Invalid base URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (system, messages) = Self.splitSystem(modelReq.messages)
        var body: [String: Any] = [
            "model": modelReq.model,
            "max_tokens": modelReq.maxOutputTokens ?? Self.defaultMaxTokens,
            "messages": messages,
        ]
        if !system.isEmpty { body["system"] = system }
        if stream { body["stream"] = true }
        if let temp = modelReq.temperature { body["temperature"] = temp }
        if !modelReq.tools.isEmpty {
            body["tools"] = modelReq.tools.map { tool -> [String: Any] in
                ["name": tool.name, "description": tool.description,
                 "input_schema": tool.inputSchema.toAnyForJSON()]
            }
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extract system/developer turns into the top-level `system` string;
    /// the Messages API rejects them inside the `messages` array. Returns
    /// the remaining user/assistant turns as wire dictionaries.
    static func splitSystem(_ messages: [ChatMessage]) -> (system: String, messages: [[String: Any]]) {
        var systemParts: [String] = []
        var wire: [[String: Any]] = []
        for msg in messages {
            switch msg.role {
            case .system, .developer:
                if !msg.content.isEmpty { systemParts.append(msg.content) }
            case .user, .tool:
                wire.append(["role": "user", "content": msg.content])
            case .assistant:
                wire.append(["role": "assistant", "content": msg.content])
            }
        }
        return (systemParts.joined(separator: "\n\n"), wire)
    }

    func parseResponse(_ data: Data, model: String) throws -> ModelResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.responseParseFailed(providerID, "Invalid JSON")
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ProviderError.requestFailed(providerID, message)
        }

        var text = ""
        var toolCalls: [ProviderToolCall] = []
        if let content = json["content"] as? [[String: Any]] {
            for block in content {
                switch block["type"] as? String {
                case "text":
                    text += (block["text"] as? String) ?? ""
                case "tool_use":
                    let argsValue = Self.jsonValue(from: block["input"])
                    toolCalls.append(ProviderToolCall(
                        id: (block["id"] as? String) ?? UUID().uuidString,
                        name: (block["name"] as? String) ?? "",
                        arguments: argsValue
                    ))
                default:
                    continue
                }
            }
        }

        var usage: ProviderUsage?
        if let u = json["usage"] as? [String: Any] {
            let input = (u["input_tokens"] as? Int) ?? 0
            let output = (u["output_tokens"] as? Int) ?? 0
            usage = ProviderUsage(promptTokens: input, completionTokens: output,
                                  totalTokens: input + output)
        }

        let responseModel = (json["model"] as? String) ?? model
        return ModelResponse(
            providerID: providerID, model: responseModel, text: text,
            toolCalls: toolCalls, finishReason: (json["stop_reason"] as? String) ?? "stop",
            usage: usage
        )
    }

    private static func jsonValue(from any: Any?) -> JSONValue {
        guard let any,
              let data = try? JSONSerialization.data(withJSONObject: any),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    static func parseStreamTextDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              parsed["type"] as? String == "content_block_delta",
              let delta = parsed["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta" else {
            return nil
        }
        return delta["text"] as? String
    }
}
