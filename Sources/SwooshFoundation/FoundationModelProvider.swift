// SwooshFoundation/FoundationModelProvider.swift — 0.9Q Apple Foundation Models
// as a SwooshCore ModelProvider
//
// Bridges Apple's on-device model to `SwooshCore.ModelProvider` so the
// agent kernel can run a turn against it — no cloud key, no network.
//
// `FoundationModelAdapter` (the control-plane wrapper) deliberately is
// *not* a chat brain. This provider is opt-in: the daemon selects it
// only when `SWOOSH_FOUNDATION_MODEL=1`. Without this file the
// FoundationModels integration had no `ModelProvider` conformance and
// no call site.
//
// **Contract notes for `complete(_:)`**:
//   • `request.options` (temperature, top-p, max-tokens, etc.) are
//     currently ignored — Apple's on-device session API does not
//     expose those knobs to third-party callers. Hosts that need
//     non-default sampling must use a different `ModelProvider`.
//   • The returned `ModelCompletionResponse.model` is always
//     `apple-on-device` regardless of `request.model`. Apple's runtime
//     picks the on-device variant; we don't get to choose.
//   • The session is cached per actor and accumulates context until
//     the actor is deinitialised. There is no per-call reset hook on
//     this provider (`FoundationModelAdapter` has one if needed).

import Foundation
import SwooshCore

public enum FoundationModelProviderError: Error, Sendable {
    /// FoundationModels is not available on this platform/build.
    case unavailable
}

#if canImport(FoundationModels)
import FoundationModels

/// `ModelProvider` backed by Apple's on-device Foundation model.
public actor FoundationModelProvider: ModelProvider {
    public nonisolated let providerID = "apple-foundation"
    public nonisolated let modelName = "apple-on-device"

    private var session: LanguageModelSession?

    public init() {}

    public func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        let session = ensureSession()
        let prompt = FoundationModelPrompt.flatten(request.messages)
        let response = try await session.respond(to: prompt)
        return ModelCompletionResponse(content: response.content, model: modelName)
    }

    private func ensureSession() -> LanguageModelSession {
        if let session { return session }
        let created = LanguageModelSession()
        session = created
        return created
    }
}
#else

/// Stub for platforms without FoundationModels — `complete` always
/// throws `.unavailable`, and the daemon never selects it there.
public actor FoundationModelProvider: ModelProvider {
    public nonisolated let providerID = "apple-foundation"
    public nonisolated let modelName = "apple-on-device"

    public init() {}

    public func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        throw FoundationModelProviderError.unavailable
    }
}
#endif

/// Prompt flattening shared by both branches.
enum FoundationModelPrompt {
    /// Flatten the transcript into a single role-tagged prompt.
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

    /// Flatten a single bare user message — used by `FoundationExecutor`
    /// where `ChatRequest` carries only one input string with no prior
    /// transcript context. Produces the same `[User]\n…\n\n[Assistant]\n`
    /// shape `flatten(_:)` emits for a one-message transcript so the
    /// model sees an explicit role tag and turn-end marker.
    static func flattenUserInput(_ input: String) -> String {
        "[User]\n\(input)\n\n[Assistant]\n"
    }
}
