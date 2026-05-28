// SwooshKit/SwooshKit.swift — The public Swift SDK
//
// SwooshKit lets any Swift developer embed agentic behavior into an app.
// This is the moat Hermes does not have.

@_exported import SwooshCore

import Foundation
import SwooshTools
import SwooshStorage

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
/// When custom stores are provided via `SwooshConfiguration`, those are
/// used. Otherwise the `InMemory*` defaults are wired so the SDK works
/// out of the box for unit tests and one-shot runs without a persistent
/// backend.
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
        // Try to open the durable SQLite backend unless overridden
        let database: SwooshDatabase? = if ProcessInfo.processInfo.environment["SWOOSH_STORAGE"] == "memory" {
            nil
        } else {
            try? SwooshDatabase()
        }

        let memoryLoader: any MemoryContextLoading
        let reportLoader: any SetupReportLoading
        let permSummarizer: any PermissionSummarizing
        let sessionStore: any SessionStoring
        let auditLogger: any ResponseAuditing

        if let db = database {
            // Durable SQLite stores
            let sqliteMemoryStore = SQLiteMemoryStore(db: db)
            memoryLoader   = config.memoryLoader   ?? SQLiteMemoryContextLoader(memoryStore: sqliteMemoryStore)
            reportLoader   = config.reportLoader   ?? SQLiteSetupReportStore(db: db)
            permSummarizer = config.permSummarizer ?? InMemoryPermSummarizer()
            sessionStore   = config.sessionStore   ?? SQLiteSessionStore(db: db)
            auditLogger    = config.auditLogger    ?? SQLiteResponseAuditor(db: db)
        } else {
            // In-memory fallback
            memoryLoader   = config.memoryLoader   ?? InMemoryMemoryLoader()
            reportLoader   = config.reportLoader   ?? InMemoryReportLoader()
            permSummarizer = config.permSummarizer ?? InMemoryPermSummarizer()
            sessionStore   = config.sessionStore   ?? InMemorySessionStore()
            auditLogger    = config.auditLogger    ?? InMemoryResponseAuditor()
        }

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
