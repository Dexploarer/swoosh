// SwooshKit/SwooshKit.swift — The public Swift SDK
//
// SwooshKit lets any Swift developer embed agentic behavior into an app.
// This is the moat Hermes does not have.

@_exported import SwooshCore

import Foundation

// MARK: - SwooshKit entry point

/// High-level entry point for embedding Swoosh into any Swift app.
///
/// Usage:
/// ```swift
/// let swoosh = try await Swoosh.configure {
///     $0.modelProvider = LocalStubProvider()
///     $0.memoryLoader = InMemoryMemoryLoader()
/// }
/// let response = try await swoosh.ask("What should we build?")
/// ```
public final class Swoosh: Sendable {
    public let kernel: AgentKernel

    private init(kernel: AgentKernel) {
        self.kernel = kernel
    }

    /// Configure and build a Swoosh instance.
    public static func configure(_ builder: (inout SwooshConfiguration) -> Void) async throws -> Swoosh {
        var config = SwooshConfiguration()
        builder(&config)
        return try await build(from: config)
    }

    /// Run a one-shot agent task.
    public func ask(_ input: String, sessionID: String = "default") async throws -> AgentResponse {
        let request = AgentRequest(sessionID: sessionID, input: input)
        return try await kernel.run(request)
    }

    // MARK: - Builder

    private static func build(from config: SwooshConfiguration) async throws -> Swoosh {
        let kernel = AgentKernel(
            memoryLoader: config.memoryLoader ?? InMemoryMemoryLoader(),
            reportLoader: config.reportLoader ?? InMemoryReportLoader(),
            permSummarizer: config.permSummarizer ?? InMemoryPermSummarizer(),
            sessionStore: config.sessionStore ?? InMemorySessionStore(),
            auditLogger: config.auditLogger ?? InMemoryResponseAuditor(),
            modelProvider: config.modelProvider ?? LocalStubProvider()
        )
        return Swoosh(kernel: kernel)
    }
}

// MARK: - Configuration

public struct SwooshConfiguration {
    public var modelProvider: (any ModelProvider)? = nil
    public var memoryLoader: (any MemoryContextLoading)? = nil
    public var reportLoader: (any SetupReportLoading)? = nil
    public var permSummarizer: (any PermissionSummarizing)? = nil
    public var sessionStore: (any SessionStoring)? = nil
    public var auditLogger: (any ResponseAuditing)? = nil

    public init() {}
}
