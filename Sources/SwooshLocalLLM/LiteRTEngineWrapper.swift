#if os(iOS)

// SwooshLocalLLM/LiteRTEngineWrapper.swift — 0.9R LiteRT-LM engine handle
//
// Thin wrapper around Google's `LiteRTLM.Engine` that exposes a
// Swoosh-friendly API: load a model from a URL, send a message and get
// a single response, or stream tokens. Both paths are async/await.

import Foundation
import LiteRTLM

public actor LiteRTEngineWrapper {

    public enum LoadState: Sendable, Equatable {
        case unloaded
        case loading
        case ready
        case failed(String)
    }

    public private(set) var loadState: LoadState = .unloaded

    private var engine: Engine?
    private var conversation: Conversation?
    private var loadedModelPath: String?

    public init() {}

    // MARK: - Lifecycle

    /// Load a `.litertlm` file from disk and bring up the engine.
    /// Idempotent — calling twice with the same path is a no-op; with a
    /// different path tears down and reloads.
    ///
    /// - Parameters:
    ///   - modelPath: URL to the `.litertlm` file on disk.
    ///   - backend: Compute backend (`.cpu()` / `.gpu`).
    ///   - tools: Optional list of LiteRT-LM `Tool` types. When supplied,
    ///     the conversation is bound to a `ToolManager` and the model
    ///     can emit function calls that the engine dispatches to each
    ///     tool's `run()` method. See `LiteRTSwooshToolBridge` for the
    ///     pattern that maps Swoosh's `SwooshTool` registry into this
    ///     shape.
    public func load(
        modelPath: URL,
        backend: Backend = .cpu(),
        tools: [Tool.Type] = []
    ) async throws {
        if loadedModelPath == modelPath.path, engine != nil, !tools.isEmpty == false {
            return
        }
        try await unload()
        loadState = .loading
        do {
            let config = try EngineConfig(modelPath: modelPath.path, backend: backend)
            let engine = Engine(engineConfig: config)
            try await engine.initialize()
            let conversationConfig: ConversationConfig? = tools.isEmpty
                ? nil
                : ConversationConfig(tools: tools.map { $0.init() })
            let conv = try await engine.createConversation(with: conversationConfig)
            self.engine = engine
            self.conversation = conv
            self.loadedModelPath = modelPath.path
            loadState = .ready
        } catch {
            loadState = .failed("\(error)")
            throw error
        }
    }

    public func unload() async throws {
        engine = nil
        conversation = nil
        loadedModelPath = nil
        loadState = .unloaded
    }

    // MARK: - Generate

    /// Single-shot generate. Returns the full response after the model
    /// finishes decoding.
    public func generate(_ text: String) async throws -> String {
        guard let conversation else {
            throw LiteRTWrapperError.notLoaded
        }
        let response = try await conversation.sendMessage(Message(text))
        return response.toString
    }

    /// Streaming generate. The async stream emits chunk text as the
    /// model decodes. Caller can append/concatenate as desired.
    public func generateStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let conversation else {
                    continuation.finish(throwing: LiteRTWrapperError.notLoaded)
                    return
                }
                let messageStream = conversation.sendMessageStream(Message(text))
                do {
                    for try await chunk in messageStream {
                        continuation.yield(chunk.toString)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Reset the conversation history without unloading the model.
    public func resetConversation() async throws {
        guard let engine else { return }
        self.conversation = try await engine.createConversation()
    }
}

// MARK: - Errors

public enum LiteRTWrapperError: Error, CustomStringConvertible {
    case notLoaded
    case loadFailed(String)

    public var description: String {
        switch self {
        case .notLoaded:        return "Local model is not loaded."
        case .loadFailed(let m):return "Local model load failed: \(m)"
        }
    }
}

#endif
