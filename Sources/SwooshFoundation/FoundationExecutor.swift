// SwooshFoundation/FoundationExecutor.swift — 0.9Q SwooshExecutor over Apple Foundation Models
//
// Conforms to `SwooshClient.SwooshExecutor` so the existing chat path
// can target Apple's on-device language model — free, private, no
// network, no entitlement requirements. Available on iOS 26+ and
// macOS 26+ where FoundationModels.framework ships.
//
// 0.9Q: routes the request through `FoundationModelPrompt.flatten` so
// that callers carrying transcript context get the same role-tagged
// rendering `FoundationModelProvider` uses. Previously only the bare
// `request.input` reached the model, silently dropping any system /
// prior-turn framing.

#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SwooshClient

public actor FoundationExecutor: SwooshExecutor {

    private var session: LanguageModelSession?

    public init() {}

    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        let session = ensureSession()
        // Use the shared prompt flattener so on-device sees an explicit
        // `[User]` tag plus an open `[Assistant]` cue — matches what
        // `FoundationModelProvider` sends for the transcript path.
        let prompt = FoundationModelPrompt.flattenUserInput(request.input)
        let response = try await session.respond(to: prompt)
        return ChatResponse(
            message: response.content,
            sessionID: request.sessionID,
            memoryIDsUsed: [],
            modelUsed: "apple-on-device",
            createdAt: Date()
        )
    }

    /// Reset the conversation context.
    public func reset() {
        session = nil
    }

    private func ensureSession() -> LanguageModelSession {
        if let session { return session }
        let created = LanguageModelSession()
        session = created
        return created
    }
}

#else

import Foundation
import SwooshClient

/// Stub on platforms without FoundationModels. Every call throws.
public actor FoundationExecutor: SwooshExecutor {
    public init() {}
    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        throw FoundationModelProviderError.unavailable
    }
}

#endif
