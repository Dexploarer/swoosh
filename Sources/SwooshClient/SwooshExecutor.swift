// SwooshClient/SwooshExecutor.swift — 0.4B Pluggable backend for chat turns
//
// The abstraction the iOS app actually talks to. Three implementations
// ship today:
//
//   • RemoteKernelExecutor — POSTs to /api/agent/chat on a paired daemon.
//     Lives here in SwooshClient (pure URLSession; iOS-buildable).
//   • LocalKernelExecutor  — runs an in-process AgentKernel. Lives in
//     SwooshKit (Mac-only because the kernel transitively depends on
//     the actantdb supervisor).
//   • FallbackExecutor     — wraps a remote + an optional local executor
//     and prefers the remote, dropping back to local on transport
//     errors. Lives in SwooshLocalLLM and is the "use Mac when
//     reachable, fall back to local" composition.
//
// Once actantDB ships an iOS-buildable Swift SDK (FFI-backed), a local
// kernel will also build on iOS and `FallbackExecutor` will work
// unchanged with both halves on-device.

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
