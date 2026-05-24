// SwooshAPI/AgentHandle.swift — 0.9S Boxed agent runner + transcript helpers
//
// `AgentHandle` is the `Sendable` union of the two ways `SwooshAPIServer`
// can drive a chat turn: a bare `AgentKernel` or the tool-loop wrapper.
// `KernelHandle` / `ToolLoopHandle` box the underlying actors so the
// public initializer stays auto-Sendable. The transcript helpers strip
// internal audit messages and translate roles for the wire format.

import Foundation
import SwooshClient
import SwooshCore

/// Sendable handle around `AgentKernel`. The kernel is already an actor, but
/// boxing it in a struct keeps the public `SwooshAPIServer` initializer
/// auto-Sendable.
struct KernelHandle: Sendable {
    let kernel: AgentKernel
    init(_ kernel: AgentKernel) { self.kernel = kernel }
}

struct ToolLoopHandle: Sendable {
    let loop: AgentToolLoop
    init(_ loop: AgentToolLoop) { self.loop = loop }
}

enum AgentHandle: Sendable {
    case kernel(KernelHandle)
    case toolLoop(ToolLoopHandle)

    func run(_ request: AgentRequest) async throws -> AgentResponse {
        switch self {
        case .kernel(let handle):
            return try await handle.kernel.run(request)
        case .toolLoop(let handle):
            return try await handle.loop.run(request).agentResponse
        }
    }

    func loadTranscript(sessionID: String) async throws -> [SwooshCore.ChatMessage] {
        switch self {
        case .kernel(let handle):
            return try await handle.kernel.loadTranscript(sessionID: sessionID)
        case .toolLoop(let handle):
            return try await handle.loop.loadTranscript(sessionID: sessionID)
        }
    }
}

func transcriptMessage(_ message: SwooshCore.ChatMessage) -> TranscriptMessage? {
    guard !isInternalAuditMessage(message.content) else { return nil }
    return TranscriptMessage(
        id: message.id,
        role: transcriptRole(message.role),
        content: message.content,
        createdAt: message.createdAt
    )
}

func isInternalAuditMessage(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("{") && trimmed.contains("\"_swoosh_audit\"")
}

func transcriptRole(_ role: SwooshCore.ChatRole) -> TranscriptRole {
    switch role {
    case .system:
        return .system
    case .user:
        return .user
    case .assistant:
        return .assistant
    case .tool:
        return .tool
    }
}
