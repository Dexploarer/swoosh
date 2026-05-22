// SwooshProviders/OpenAIResponsesProvider.swift — 0.9P OpenAI Responses API
//
// Real HTTP calls to api.openai.com/v1/responses. Bearer API key from Keychain.
// Streaming SSE. Tool call parsing. Usage tracking.

import Foundation
import SwooshSecrets
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - OpenAI Responses Provider
// ═══════════════════════════════════════════════════════════════════

public actor OpenAIResponsesProvider: ToolCallingModelProviding, EmbeddingProviding {
    public nonisolated let providerID: ProviderID = "openai"
    public nonisolated let displayName: String = "OpenAI API"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: true, toolCalling: true, structuredOutput: true,
        embeddings: true, vision: true
    )

    private let secrets: any SecretStoring
    private let http: any HTTPClient
    private let baseURL: String

    public init(secrets: any SecretStoring, http: any HTTPClient = URLSessionHTTPClient(),
                baseURL: String = "https://api.openai.com") {
        self.secrets = secrets; self.http = http; self.baseURL = baseURL
    }

    // ── Complete (non-streaming) ──────────────────────────────────

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        let apiKey = try await loadAPIKey()
        let httpReq = try buildRequest(apiKey: apiKey, modelReq: request, stream: false)
        let response = try await http.send(httpReq)
        return try parseResponse(response.data, model: request.model)
    }

    // ── Complete with tools ───────────────────────────────────────

    public func completeWithTools(
        _ request: ModelRequest, tools: [ToolDescriptor]
    ) async throws -> ModelResponse {
        var req = request
        req.tools = tools
        return try await complete(req)
    }

    // ── Embeddings ─────────────────────────────────────────────────

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
        let apiKey = try await loadAPIKey()
        let httpReq = try buildEmbeddingRequest(apiKey: apiKey, embeddingReq: request)
        let response = try await http.send(httpReq)
        return try parseEmbeddingResponse(response.data, model: request.model)
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
                        guard let line = String(data: chunk, encoding: .utf8) else { continue }
                        // SSE format: data: {...}
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        if json == "[DONE]" { break }

                        if let event = self.parseStreamChunk(json) {
                            switch event {
                            case .textDelta(let text):
                                accumulated += text
                                continuation.yield(event)
                            case .toolCallDelta(let tc):
                                toolCalls.append(tc)
                                continuation.yield(event)
                            default:
                                continuation.yield(event)
                            }
                        }
                    }
                    // Emit final done
                    let finalResponse = ModelResponse(
                        providerID: self.providerID, model: request.model,
                        text: accumulated, toolCalls: toolCalls, finishReason: "stop"
                    )
                    continuation.yield(.done(finalResponse))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // ── Internal ──────────────────────────────────────────────────

    private func loadAPIKey() async throws -> String {
        do {
            return try await secrets.get(SecretRef("openai", "api_key"))
        } catch {
            throw ProviderError.authMissing(providerID,
                "OpenAI API key not found. Run: swoosh provider auth openai --api-key")
        }
    }

    private func buildRequest(apiKey: String, modelReq: ModelRequest, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw ProviderError.requestFailed(providerID, "Invalid base URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Swoosh/0.9P", forHTTPHeaderField: "User-Agent")

        // Build Responses API body
        var body: [String: Any] = [
            "model": modelReq.model,
            "input": modelReq.messages.map { msg -> [String: Any] in
                var m: [String: Any] = ["role": msg.role.rawValue, "content": msg.content]
                if let id = msg.toolCallID { m["tool_call_id"] = id }
                return m
            },
        ]

        if stream { body["stream"] = true }
        if let temp = modelReq.temperature { body["temperature"] = temp }
        if let max = modelReq.maxOutputTokens { body["max_output_tokens"] = max }
        if let instructions = modelReq.instructions { body["instructions"] = instructions }
        if let effort = modelReq.reasoningEffort {
            body["reasoning"] = ["effort": effort.openAIWireValue]
        }

        // Tools
        if !modelReq.tools.isEmpty {
            body["tools"] = modelReq.tools.map { tool -> [String: Any] in
                [
                    "type": "function",
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema.toAnyForJSON(),
                ]
            }
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func buildEmbeddingRequest(apiKey: String, embeddingReq: EmbeddingRequest) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/v1/embeddings") else {
            throw ProviderError.requestFailed(providerID, "Invalid base URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Swoosh/0.9P", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": embeddingReq.model,
            "input": embeddingReq.input,
            "encoding_format": "float",
        ])
        return req
    }

    private func parseResponse(_ data: Data, model: String) throws -> ModelResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.responseParseFailed(providerID, "Invalid JSON")
        }

        // Check for API errors
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ProviderError.requestFailed(providerID, message)
        }

        // Parse output array
        var text = ""
        var toolCalls: [ProviderToolCall] = []
        var usageInfo: ProviderUsage?

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                let type = item["type"] as? String
                if type == "message" {
                    if let content = item["content"] as? [[String: Any]] {
                        for part in content {
                            if part["type"] as? String == "output_text" {
                                text += (part["text"] as? String) ?? ""
                            }
                        }
                    }
                } else if type == "function_call" {
                    let tc = ProviderToolCall(
                        id: (item["call_id"] as? String) ?? UUID().uuidString,
                        name: (item["name"] as? String) ?? "",
                        arguments: .string((item["arguments"] as? String) ?? "{}")
                    )
                    toolCalls.append(tc)
                }
            }
        }

        // Parse usage
        if let usage = json["usage"] as? [String: Any] {
            usageInfo = ProviderUsage(
                promptTokens: (usage["input_tokens"] as? Int) ?? 0,
                completionTokens: (usage["output_tokens"] as? Int) ?? 0,
                totalTokens: (usage["total_tokens"] as? Int) ?? 0
            )
        }

        let responseModel = (json["model"] as? String) ?? model

        return ModelResponse(
            providerID: providerID, model: responseModel, text: text,
            toolCalls: toolCalls, finishReason: "stop", usage: usageInfo
        )
    }

    private func parseEmbeddingResponse(_ data: Data, model: String) throws -> EmbeddingResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.responseParseFailed(providerID, "Invalid JSON")
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ProviderError.requestFailed(providerID, message)
        }

        guard let data = json["data"] as? [[String: Any]] else {
            throw ProviderError.responseParseFailed(providerID, "Missing embedding data")
        }

        var embeddings: [[Double]] = []
        embeddings.reserveCapacity(data.count)
        for item in data {
            embeddings.append(try parseEmbeddingVector(item["embedding"]))
        }

        var usageInfo: ProviderUsage?
        if let rawUsage = json["usage"] {
            guard let usage = rawUsage as? [String: Any],
                  let promptTokens = usage["prompt_tokens"] as? Int,
                  let totalTokens = usage["total_tokens"] as? Int else {
                throw ProviderError.responseParseFailed(providerID, "Invalid embedding usage")
            }
            usageInfo = ProviderUsage(
                promptTokens: promptTokens,
                completionTokens: 0,
                totalTokens: totalTokens
            )
        }

        let responseModel = (json["model"] as? String) ?? model
        return EmbeddingResponse(
            providerID: providerID,
            model: responseModel,
            embeddings: embeddings,
            usage: usageInfo
        )
    }

    private func parseEmbeddingVector(_ value: Any?) throws -> [Double] {
        if let vector = value as? [Double] {
            return vector
        }
        if let vector = value as? [NSNumber] {
            return vector.map(\.doubleValue)
        }
        throw ProviderError.responseParseFailed(providerID, "Invalid embedding vector")
    }

    private func parseStreamChunk(_ json: String) -> ModelStreamEvent? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let type = parsed["type"] as? String

        // Response created / output item
        if type == "response.output_text.delta" {
            if let delta = parsed["delta"] as? String {
                return .textDelta(delta)
            }
        }

        // Function call output
        if type == "response.function_call_arguments.done" {
            let tc = ProviderToolCall(
                id: (parsed["call_id"] as? String) ?? UUID().uuidString,
                name: (parsed["name"] as? String) ?? "",
                arguments: .string((parsed["arguments"] as? String) ?? "{}")
            )
            return .toolCallDelta(tc)
        }

        // Usage
        if type == "response.completed" {
            if let response = parsed["response"] as? [String: Any],
               let usage = response["usage"] as? [String: Any] {
                return .usage(ProviderUsage(
                    promptTokens: (usage["input_tokens"] as? Int) ?? 0,
                    completionTokens: (usage["output_tokens"] as? Int) ?? 0,
                    totalTokens: (usage["total_tokens"] as? Int) ?? 0
                ))
            }
        }

        return nil
    }
}
