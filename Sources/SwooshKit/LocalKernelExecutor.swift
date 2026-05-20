// SwooshKit/LocalKernelExecutor.swift — In-process SwooshExecutor
//
// Wraps an `AgentKernel` in the `SwooshExecutor` protocol from
// SwooshClient so the Mac dashboard (and tests) can use the same chat
// surface as the iOS app — one abstraction, two implementations. The
// translation between `ChatRequest`/`ChatResponse` (wire types) and
// `AgentRequest`/`AgentResponse` (kernel types) lives here so neither
// SwooshClient nor SwooshCore needs to know about the other.

import Foundation
import SwooshClient

/// `SwooshExecutor` backed by an in-process `AgentKernel`.
///
/// macOS/Linux only because SwooshKit itself only builds there (the
/// transitive `ActantDBSupervisor` dependency uses `Foundation.Process`).
/// When actantDB grows an iOS-buildable SDK, an iOS-side equivalent of
/// this type will land alongside it.
public struct LocalKernelExecutor: SwooshExecutor {
    public let kernel: AgentKernel

    public init(kernel: AgentKernel) {
        self.kernel = kernel
    }

    public init(swoosh: Swoosh) {
        self.kernel = swoosh.kernel
    }

    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        let agentRequest = AgentRequest(
            sessionID: request.sessionID,
            input: request.input
        )
        let response = try await kernel.run(agentRequest)
        return ChatResponse(
            message: response.message,
            sessionID: response.sessionID,
            memoryIDsUsed: response.memoryIDsUsed,
            modelUsed: response.modelUsed,
            createdAt: response.createdAt
        )
    }
}
