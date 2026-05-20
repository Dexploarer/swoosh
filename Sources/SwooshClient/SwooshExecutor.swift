// SwooshClient/SwooshExecutor.swift — Pluggable backend for chat turns
//
// The abstraction the iOS app actually talks to. Two implementations land
// in this slice:
//
//   • RemoteKernelExecutor — POSTs to /api/agent/chat on a paired daemon.
//     Lives here in SwooshClient (pure URLSession; iOS-buildable).
//   • LocalKernelExecutor  — runs an in-process AgentKernel. Lives in
//     SwooshKit (Mac-only today because the kernel transitively depends
//     on the actantdb supervisor).
//
// Once actantDB ships an iOS-buildable Swift SDK (FFI-backed), a third
// implementation can register a local kernel on iOS too, and a
// `RoutedExecutor` can pick "use Mac when reachable, fall back to local"
// without any caller changes.

import Foundation

/// Abstract chat backend. One `run(_:)` call = one agent turn.
public protocol SwooshExecutor: Sendable {
    func run(_ request: ChatRequest) async throws -> ChatResponse
}

/// `SwooshExecutor` backed by a remote `swooshd` over HTTP.
public struct RemoteKernelExecutor: SwooshExecutor {
    public let client: SwooshAPIClient

    public init(client: SwooshAPIClient) {
        self.client = client
    }

    public func run(_ request: ChatRequest) async throws -> ChatResponse {
        try await client.chat(request)
    }
}
