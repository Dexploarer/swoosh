// SwooshProviders/LocalOpenAICompatibleProvider.swift — 0.9P Local Provider
//
// Ollama, LM Studio, vLLM, llama.cpp servers — anything OpenAI-compatible at localhost.
// No auth by default. Localhost-only network policy.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local OpenAI-Compatible Provider
// ═══════════════════════════════════════════════════════════════════

public actor LocalOpenAICompatibleProvider: StreamingModelProviding {
    public nonisolated let providerID: ProviderID = "local-openai"
    public nonisolated let displayName: String = "Local OpenAI-Compatible"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: true, toolCalling: true, structuredOutput: false,
        embeddings: true, vision: false
    )

    private let http: any HTTPClient
    private let baseURL: String

    public init(http: any HTTPClient = URLSessionHTTPClient(),
                baseURL: String = "http://127.0.0.1:11434/v1") {
        self.http = http; self.baseURL = baseURL
    }

    // ── Network policy ────────────────────────────────────────────

    private func validateLocalhost() throws {
        guard baseURL.contains("127.0.0.1") || baseURL.contains("localhost")
              || baseURL.contains("[::1]") else {
            throw ProviderError.requestFailed(providerID,
                "Local provider only supports localhost. Got: \(baseURL)")
        }
    }

    // ── Complete ──────────────────────────────────────────────────

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        try validateLocalhost()
        let httpReq = try buildChatCompletionsRequest(request, stream: false)
        let response = try await http.send(httpReq)
        return try parseChatCompletionsResponse(response.data, model: request.model)
    }

    // ── Stream ────────────────────────────────────────────────────

    public func stream(_ request: ModelRequest) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        try validateLocalhost()
        let httpReq = try buildChatCompletionsRequest(request, stream: true)
        let (_, dataStream) = try await http.sendStreaming(httpReq)

        return AsyncThrowingStream { continuation in
            Task {
                var accumulated = ""
                do {
                    for try await chunk in dataStream {
                        guard let line = String(data: chunk, encoding: .utf8),
                              line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        if json == "[DONE]" { break }
                        if let delta = self.parseStreamDelta(json) {
                            accumulated += delta
                            continuation.yield(.textDelta(delta))
                        }
                    }
                    let final = ModelResponse(
                        providerID: self.providerID, model: request.model,
                        text: accumulated, finishReason: "stop"
                    )
                    continuation.yield(.done(final))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // ── Model discovery ───────────────────────────────────────────

    public func listModels() async throws -> [String] {
        try validateLocalhost()
        guard let url = URL(string: "\(baseURL)/models") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let response = try await http.send(req)

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else { return [] }
        return data.compactMap { $0["id"] as? String }
    }

    // ── Health check ──────────────────────────────────────────────

    public func isReachable() async -> Bool {
        do {
            _ = try await listModels()
            return true
        } catch {
            return false
        }
    }

    // ── Internals ─────────────────────────────────────────────────

    private func buildChatCompletionsRequest(_ modelReq: ModelRequest, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw ProviderError.requestFailed(providerID, "Invalid base URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": modelReq.model,
            "messages": modelReq.messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        if stream { body["stream"] = true }
        if let temp = modelReq.temperature { body["temperature"] = temp }
        if let max = modelReq.maxOutputTokens { body["max_tokens"] = max }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func parseChatCompletionsResponse(_ data: Data, model: String) throws -> ModelResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw ProviderError.responseParseFailed(providerID, "Invalid response")
        }

        let text = (message["content"] as? String) ?? ""
        let responseModel = (json["model"] as? String) ?? model

        var usage: ProviderUsage?
        if let u = json["usage"] as? [String: Any] {
            usage = ProviderUsage(
                promptTokens: (u["prompt_tokens"] as? Int) ?? 0,
                completionTokens: (u["completion_tokens"] as? Int) ?? 0,
                totalTokens: (u["total_tokens"] as? Int) ?? 0
            )
        }

        return ModelResponse(
            providerID: providerID, model: responseModel, text: text,
            finishReason: "stop", usage: usage
        )
    }

    private func parseStreamDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = parsed["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else { return nil }
        return content
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local provider discovery
// ═══════════════════════════════════════════════════════════════════

public struct LocalProviderDiscovery: Sendable {
    public struct DiscoveredProvider: Sendable {
        public let name: String
        public let baseURL: String
        public let models: [String]
    }

    public init() {}

    /// Probe common local inference endpoints
    public func discover() async -> [DiscoveredProvider] {
        let http = URLSessionHTTPClient()
        var found: [DiscoveredProvider] = []

        let endpoints = [
            ("Ollama", "http://127.0.0.1:11434/v1"),
            ("LM Studio", "http://127.0.0.1:1234/v1"),
            ("vLLM", "http://127.0.0.1:8000/v1"),
            ("llama.cpp", "http://127.0.0.1:8080/v1"),
        ]

        for (name, base) in endpoints {
            guard let url = URL(string: "\(base)/models") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 2

            do {
                let response = try await http.send(req)
                if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                   let data = json["data"] as? [[String: Any]] {
                    let models = data.compactMap { $0["id"] as? String }
                    found.append(DiscoveredProvider(name: name, baseURL: base, models: models))
                }
            } catch {
                continue
            }
        }

        return found
    }
}
