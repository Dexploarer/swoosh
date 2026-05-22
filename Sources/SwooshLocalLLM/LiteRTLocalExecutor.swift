#if os(iOS)

// SwooshLocalLLM/LiteRTLocalExecutor.swift — 0.9R SwooshExecutor over local LiteRT
//
// Conforms to `SwooshClient.SwooshExecutor` so the existing chat code
// path (used by iOS ChatScreen + macOS AgentShellModel) can target the
// local model with no other changes. When the daemon is unreachable,
// `ProviderRouter` can fall through to this.

import Foundation
import LiteRTLM
import SwooshClient

public actor LiteRTLocalExecutor: SwooshExecutor {

    private let wrapper: LiteRTEngineWrapper
    private let model: LiteRTModel
    private let tools: [Tool.Type]

    public init(
        model: LiteRTModel = LiteRTModelCatalog.defaultModel,
        tools: [Tool.Type] = [SwooshDispatchTool.self]
    ) {
        self.wrapper = LiteRTEngineWrapper()
        self.model = model
        self.tools = tools
    }

    /// Bring the model up if it isn't already. Returns when ready.
    public func ensureReady(modelPath: URL) async throws {
        try await wrapper.load(modelPath: modelPath, tools: tools)
    }

    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        let text = try await wrapper.generate(request.input)
        return ChatResponse(
            message: text,
            sessionID: request.sessionID,
            memoryIDsUsed: [],
            modelUsed: model.id,
            createdAt: Date()
        )
    }

    /// Streaming variant for callers that can render chunks live.
    /// Not part of `SwooshExecutor` (which is single-shot). Wire to
    /// `AgentShellModel.send` via a streaming-aware closure when ready.
    public nonisolated func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let inner = await self.wrapper.generateStream(request.input)
                do {
                    for try await chunk in inner {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public var loadState: LiteRTEngineWrapper.LoadState {
        get async { await wrapper.loadState }
    }

    public func reset() async throws {
        try await wrapper.resetConversation()
    }
}

#endif
