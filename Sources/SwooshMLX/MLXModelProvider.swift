// SwooshMLX/MLXModelProvider.swift — MLX local inference as a ModelProvider — 0.9P
//
// Bridges the on-device `MLXInferenceEngine` to `SwooshCore.ModelProvider`
// so the agent kernel can run a full turn entirely locally — no cloud
// key, no network. The daemon selects this provider when
// `SWOOSH_MLX_MODEL` names a model directory under `~/.swoosh/models`.
//
// Without this bridge `MLXInferenceEngine` has no call site — the
// "MLX-capable, Apple-first" runtime is unreachable. This file is the
// missing last mile.

import Foundation
import SwooshCore

/// `ModelProvider` that runs inference on-device via MLX. The model is
/// loaded lazily on the first `complete` call and kept resident.
public actor MLXModelProvider: ModelProvider {
    public nonisolated let providerID = "mlx-local"
    public nonisolated let modelName: String

    private let engine: MLXInferenceEngine
    private let modelID: String
    private let maxTokens: Int
    private let temperature: Double

    /// - Parameters:
    ///   - modelID: directory name of the model under `modelsDir`.
    ///   - modelsDir: model root (default `~/.swoosh/models`).
    public init(
        modelID: String,
        modelsDir: URL? = nil,
        maxTokens: Int = 512,
        temperature: Double = 0.7
    ) {
        self.modelID = modelID
        self.modelName = modelID
        self.engine = MLXInferenceEngine(modelsDir: modelsDir)
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    public func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        if await engine.currentModel() != modelID {
            try await engine.loadModel(id: modelID)
        }
        let prompt = Self.flatten(request.messages)
        let output = try await engine.generate(
            prompt: prompt, maxTokens: maxTokens, temperature: temperature
        )
        return ModelCompletionResponse(content: output, model: modelID)
    }

    /// Flatten the transcript into a single role-tagged prompt. MLX's
    /// `ChatSession` applies the model's own chat template on top.
    static func flatten(_ messages: [ChatMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            let tag: String
            switch message.role {
            case .system:    tag = "System"
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
