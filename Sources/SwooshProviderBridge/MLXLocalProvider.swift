// SwooshProviderBridge/MLXLocalProvider.swift — MLX-backed local provider — 0.9A
//
// Conforms to `SwooshProviders.ModelProviding`. Holds an `MLXInferenceEngine`
// and serves `complete(_:)` requests by flattening chat messages into a
// single prompt string and forwarding to MLX. Streaming + tool-calling are
// not yet supported on the MLX path; capabilities advertise that.

import Foundation
import SwooshMLX
import SwooshModels
import SwooshProviders
import SwooshTools

public actor MLXLocalProvider: SwooshProviders.ModelProviding {
    public nonisolated let providerID = ProviderID(ModelDefaults.localMLXProviderID)
    public nonisolated let displayName = "MLX Local"
    public nonisolated let capabilities = ProviderCapabilities(
        streaming: false,
        toolCalling: false,
        structuredOutput: true,
        embeddings: false,
        vision: true
    )

    private let engine: MLXInferenceEngine

    public init(engine: MLXInferenceEngine = MLXInferenceEngine()) {
        self.engine = engine
    }

    public func complete(
        _ request: SwooshProviders.ModelRequest
    ) async throws -> SwooshProviders.ModelResponse {
        let model = Self.resolvedModel(request.model)
        if await engine.currentModel() != model {
            try await engine.loadModel(id: model)
        }
        let output = try await engine.generate(
            prompt: Self.flatten(request.messages),
            maxTokens: request.maxOutputTokens ?? 512,
            temperature: request.temperature ?? 0.7
        )
        return SwooshProviders.ModelResponse(
            providerID: providerID,
            model: model,
            text: output
        )
    }

    private static func resolvedModel(_ model: String) -> String {
        guard !model.isEmpty, model != "auto" else {
            return ModelDefaults.localMLXModelID
        }
        return model
    }

    /// Flatten chat messages into a tag-prefixed prompt string. The
    /// switch covers all 5 cases of `SwooshTools.ChatMessage.role` so a
    /// future role addition trips the compiler instead of silently
    /// dropping content.
    private static func flatten(_ messages: [SwooshTools.ChatMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            let tag: String
            switch message.role {
            case .system:    tag = "System"
            case .developer: tag = "Developer"
            case .user:      tag = "User"
            case .assistant: tag = "Assistant"
            case .tool:      tag = "Tool"
            }
            lines.append("[\(tag)]\n\(message.content)")
        }
        lines.append("[Assistant]\n")
        return lines.joined(separator: "\n\n")
    }
}
