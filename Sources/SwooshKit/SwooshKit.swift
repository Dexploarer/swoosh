// SwooshKit/SwooshKit.swift — The public Swift SDK
//
// SwooshKit lets any Swift developer embed agentic behavior into an app.
// This is the moat Hermes does not have.

@_exported import SwooshCore

import Foundation
import ActantDB
import ActantAgent
import SwooshActantBackend
import SwooshTools

// MARK: - SwooshKit entry point

/// High-level entry point for embedding Swoosh into any Swift app.
///
/// Usage:
/// ```swift
/// let swoosh = try await Swoosh.configure {
///     $0.modelProvider = LocalDiagnosticProvider()
/// }
/// let response = try await swoosh.ask("What should we build?")
/// ```
///
/// When `ACTANT_BASE_URL` is set in the process environment, every default
/// loader/store/auditor is wired through ActantDB via SwooshActantBackend's
/// conformance extensions. Otherwise the `InMemory*` defaults are used so
/// unit tests work without a server.
public final class Swoosh: Sendable {
    public let kernel: AgentKernel
    public let toolLoop: AgentToolLoop?

    private init(kernel: AgentKernel, toolLoop: AgentToolLoop?) {
        self.kernel = kernel
        self.toolLoop = toolLoop
    }

    /// Configure and build a Swoosh instance.
    public static func configure(
        _ builder: @Sendable (inout SwooshConfiguration) -> Void
    ) async throws -> Swoosh {
        var config = SwooshConfiguration()
        builder(&config)
        return try await build(from: config)
    }

    /// Run a one-shot agent task.
    public func ask(_ input: String, sessionID: String = "default") async throws -> AgentResponse {
        let request = AgentRequest(sessionID: sessionID, input: input)
        if let toolLoop {
            return try await toolLoop.run(request).agentResponse
        }
        return try await kernel.run(request)
    }

    // MARK: - Builder

    private static func build(from config: SwooshConfiguration) async throws -> Swoosh {
        let env = ProcessInfo.processInfo.environment
        let actantBackend: AgentBackend? = {
            guard let raw = env["ACTANT_BASE_URL"], let url = URL(string: raw) else { return nil }
            return AgentBackend(
                client: ActantClient(baseURL: url, token: env["ACTANT_TOKEN"]),
                workspaceID: env["ACTANT_WORKSPACE_ID"] ?? "ws_swoosh",
                actorID: env["ACTANT_ACTOR_ID"] ?? "act_swoosh"
            )
        }()

        let memoryLoader   = config.memoryLoader   ?? actantBackend.map { MemoryStore(backend: $0) } ?? InMemoryMemoryLoader()
        let reportLoader   = config.reportLoader   ?? actantBackend.map { MemoryStore(backend: $0) } ?? InMemoryReportLoader()
        let permSummarizer = config.permSummarizer ?? actantBackend.map { ApprovalCenter(backend: $0) } ?? InMemoryPermSummarizer()
        let sessionStore   = config.sessionStore   ?? actantBackend.map { SwooshSessionStore(backend: $0) } ?? InMemorySessionStore()
        let auditLogger    = config.auditLogger    ?? actantBackend.map { SwooshResponseAuditor(backend: $0) } ?? InMemoryResponseAuditor()

        let modelProvider = config.modelProvider ?? LocalDiagnosticProvider()
        let kernel = AgentKernel(
            memoryLoader: memoryLoader,
            reportLoader: reportLoader,
            permSummarizer: permSummarizer,
            sessionStore: sessionStore,
            auditLogger: auditLogger,
            modelProvider: modelProvider,
            skillCatalogProvider: config.skillCatalogProvider
        )
        let toolLoop = config.toolRegistry.map {
            AgentToolLoop(
                memoryLoader: memoryLoader,
                reportLoader: reportLoader,
                permSummarizer: permSummarizer,
                sessionStore: sessionStore,
                auditLogger: auditLogger,
                modelProvider: modelProvider,
                toolRegistry: $0,
                policy: config.toolPolicy,
                skillCatalogProvider: config.skillCatalogProvider
            )
        }
        return Swoosh(kernel: kernel, toolLoop: toolLoop)
    }
}

// MARK: - Configuration

public struct SwooshConfiguration: Sendable {
    public var modelProvider: (any ModelProvider)? = nil
    public var memoryLoader: (any MemoryContextLoading)? = nil
    public var reportLoader: (any SetupReportLoading)? = nil
    public var permSummarizer: (any PermissionSummarizing)? = nil
    public var sessionStore: (any SessionStoring)? = nil
    public var auditLogger: (any ResponseAuditing)? = nil
    public var toolRegistry: ToolRegistry? = nil
    public var toolPolicy: ToolCallPolicy = .defaultAgent
    /// Optional Level-0 skill catalog provider. When set, the kernel and
    /// tool loop inject `(id, title, description)` for every promotable
    /// skill into the system prompt.
    public var skillCatalogProvider: SkillCatalogProviding? = nil

    public init() {}
}
