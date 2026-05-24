// SwooshCore/AgentKernel.swift — 0.9S Personalized Agent Kernel
//
// The kernel takes a request, builds a prompt from approved context only,
// calls the model, records which memories were used, and returns a response.
//
// Hard rules:
// - Only approved memories enter the prompt
// - Rejected candidates NEVER enter the prompt
// - Raw Scout records NEVER enter the prompt by default
// - Cookies, secrets, and private keys NEVER enter the prompt
// - Every response records memory IDs used (for /why)
// - Every response creates an audit event

import Foundation
import SwooshTools

// MARK: - Agent request / response

public struct AgentRequest: Sendable {
    public let sessionID: String
    public let input: String
    public let mode: AgentMode
    public let model: String?
    public let providerID: String?

    public init(
        sessionID: String = "default",
        input: String,
        mode: AgentMode = .standard,
        model: String? = nil,
        providerID: String? = nil
    ) {
        self.sessionID = sessionID
        self.input = input
        self.mode = mode
        self.model = model
        self.providerID = providerID
    }
}

public enum AgentMode: String, Sendable {
    case standard      // normal chat
    case developer     // code-aware
    case scout         // personalization scan mode
    case minimal       // minimal context for speed
}

public struct AgentResponse: Sendable {
    public let message: String
    public let sessionID: String
    public let memoryIDsUsed: [String]
    public let setupReportUsed: Bool
    public let permissionSummaryUsed: Bool
    public let modelUsed: String
    public let createdAt: Date

    public init(
        message: String,
        sessionID: String,
        memoryIDsUsed: [String] = [],
        setupReportUsed: Bool = false,
        permissionSummaryUsed: Bool = false,
        modelUsed: String = "unknown",
        createdAt: Date = Date()
    ) {
        self.message = message
        self.sessionID = sessionID
        self.memoryIDsUsed = memoryIDsUsed
        self.setupReportUsed = setupReportUsed
        self.permissionSummaryUsed = permissionSummaryUsed
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}

// MARK: - Context loading protocols

/// Loads only approved memories. Rejected candidates and raw Scout records are excluded.
public protocol MemoryContextLoading: Sendable {
    func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)]
}

/// Loads the latest setup report summary for prompt injection.
public protocol SetupReportLoading: Sendable {
    func loadLatestSetupReport() async throws -> String?
}

/// Generates a permission summary for prompt injection.
public protocol PermissionSummarizing: Sendable {
    func permissionSummary() async throws -> String
}

/// Persists chat messages for session continuation.
public protocol SessionStoring: Sendable {
    func appendMessage(sessionID: String, message: ChatMessage) async throws
    func loadTranscript(sessionID: String) async throws -> [ChatMessage]
}

/// Logs response audit metadata (for /why).
public protocol ResponseAuditing: Sendable {
    func logResponseAudit(_ audit: ResponseAuditRecord) async throws
    func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord?
}

// MARK: - Chat message

public struct ChatMessage: Sendable, Codable, Identifiable {
    public let id: String
    public let role: ChatRole
    public let content: String
    public let createdAt: Date

    public init(id: String = UUID().uuidString, role: ChatRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum ChatRole: String, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Response audit record (for /why)

public struct ResponseAuditRecord: Sendable, Codable {
    public let sessionID: String
    public let responseID: String
    public let modelUsed: String
    public let memoryIDsUsed: [String]
    public let setupReportUsed: Bool
    public let permissionSummaryUsed: Bool
    public let rejectedMemoriesExcluded: Bool
    public let rawScoutRecordsExcluded: Bool
    public let cookiesExcluded: Bool
    public let secretsExcluded: Bool
    public let createdAt: Date

    public init(
        sessionID: String,
        responseID: String = UUID().uuidString,
        modelUsed: String,
        memoryIDsUsed: [String],
        setupReportUsed: Bool,
        permissionSummaryUsed: Bool,
        rejectedMemoriesExcluded: Bool = true,
        rawScoutRecordsExcluded: Bool = true,
        cookiesExcluded: Bool = true,
        secretsExcluded: Bool = true,
        createdAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.responseID = responseID
        self.modelUsed = modelUsed
        self.memoryIDsUsed = memoryIDsUsed
        self.setupReportUsed = setupReportUsed
        self.permissionSummaryUsed = permissionSummaryUsed
        self.rejectedMemoriesExcluded = rejectedMemoriesExcluded
        self.rawScoutRecordsExcluded = rawScoutRecordsExcluded
        self.cookiesExcluded = cookiesExcluded
        self.secretsExcluded = secretsExcluded
        self.createdAt = createdAt
    }
}

// MARK: - Model provider

public struct ModelCompletionRequest: Sendable {
    public let messages: [ChatMessage]
    public let model: String?
    public let providerID: String?
    public let tools: [SwooshTools.ToolDescriptor]

    public init(
        messages: [ChatMessage],
        model: String? = nil,
        providerID: String? = nil,
        tools: [SwooshTools.ToolDescriptor] = []
    ) {
        self.messages = messages
        self.model = model
        self.providerID = providerID
        self.tools = tools
    }
}

public struct ModelCompletionResponse: Sendable {
    public let content: String
    public let model: String
    public let usage: ModelUsage
    public let toolCalls: [NativeToolCall]
    public let isToolCallMode: Bool

    public init(
        content: String,
        model: String,
        usage: ModelUsage = ModelUsage(),
        toolCalls: [NativeToolCall] = [],
        isToolCallMode: Bool = false
    ) {
        self.content = content
        self.model = model
        self.usage = usage
        self.toolCalls = toolCalls
        self.isToolCallMode = isToolCallMode
    }
}

public struct ModelUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0, totalTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

/// Abstract model provider — concrete implementations for MLX, OpenAI, etc.
public protocol ModelProvider: Sendable {
    var providerID: String { get }
    var modelName: String { get }
    func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse
}


// MARK: - Skill catalog provider

/// Loads the Level-0 skill catalog — `(id, title, description)` per
/// promotable skill — for system-prompt injection. Returns `[]` when no
/// skill store is wired (CLI one-shots, unit tests). Kept as a closure so
/// `SwooshCore` need not depend on `SwooshSkills`.
public typealias SkillCatalogProviding =
    @Sendable () async -> [(id: String, title: String, description: String)]

// MARK: - Agent kernel actor

/// The personalized agent kernel.
/// Takes a request, builds a prompt from approved-only context,
/// calls the model, and records what context was used.
public actor AgentKernel {
    private let memoryLoader: any MemoryContextLoading
    private let reportLoader: any SetupReportLoading
    private let permSummarizer: any PermissionSummarizing
    private let sessionStore: any SessionStoring
    private let auditLogger: any ResponseAuditing
    private let modelProvider: any ModelProvider
    private let promptBuilder: PromptBuilder
    private let skillCatalogProvider: SkillCatalogProviding?

    public init(
        memoryLoader: any MemoryContextLoading,
        reportLoader: any SetupReportLoading,
        permSummarizer: any PermissionSummarizing,
        sessionStore: any SessionStoring,
        auditLogger: any ResponseAuditing,
        modelProvider: any ModelProvider,
        promptBuilder: PromptBuilder = PromptBuilder(),
        skillCatalogProvider: SkillCatalogProviding? = nil
    ) {
        self.memoryLoader = memoryLoader
        self.reportLoader = reportLoader
        self.permSummarizer = permSummarizer
        self.sessionStore = sessionStore
        self.auditLogger = auditLogger
        self.modelProvider = modelProvider
        self.promptBuilder = promptBuilder
        self.skillCatalogProvider = skillCatalogProvider
    }

    public func loadTranscript(sessionID: String) async throws -> [ChatMessage] {
        try await sessionStore.loadTranscript(sessionID: sessionID)
    }

    /// Run an agent request and return a response with full audit metadata.
    public func run(_ request: AgentRequest) async throws -> AgentResponse {
        // 1. Load approved context ONLY
        let memories = try await memoryLoader.loadApprovedMemories()
        let report = try await reportLoader.loadLatestSetupReport()
        let permSummary = try await permSummarizer.permissionSummary()

        // 2. Build system prompt (privacy boundary)
        let skillCatalog = await skillCatalogProvider?() ?? []
        let mappedMemories = memories.map {
            ApprovedMemory(id: $0.id, text: $0.text, category: $0.category)
        }
        let mappedSkills = skillCatalog.map {
            SkillCatalogEntry(id: $0.id, title: $0.title, description: $0.description)
        }
        let promptResult = promptBuilder.buildSystemPrompt(
            approvedMemories: mappedMemories,
            setupReport: report,
            permissionSummary: permSummary,
            skillCatalog: mappedSkills
        )
        let systemPrompt = promptResult.prompt
        let memoryIDs = promptResult.memoryIDs

        // 3. Load existing transcript for session continuation
        let storedTranscript = try await sessionStore.loadTranscript(sessionID: request.sessionID)
        let priorSystemPrompt = storedTranscript.first(where: { $0.role == .system })?.content
        var transcript = storedTranscript.filter { $0.role != .system }

        // 4. Prepend the current system prompt
        let systemMsg = ChatMessage(role: .system, content: systemPrompt)
        transcript.insert(systemMsg, at: 0)
        if priorSystemPrompt != systemPrompt {
            try await sessionStore.appendMessage(sessionID: request.sessionID, message: systemMsg)
        }

        // 5. Append user message
        let userMsg = ChatMessage(role: .user, content: request.input)
        transcript.append(userMsg)
        try await sessionStore.appendMessage(sessionID: request.sessionID, message: userMsg)

        // 6. Call model
        let completionRequest = ModelCompletionRequest(
            messages: transcript,
            model: request.model,
            providerID: request.providerID
        )
        let completion = try await modelProvider.complete(completionRequest)

        // 7. Append assistant response
        let assistantMsg = ChatMessage(role: .assistant, content: completion.content)
        try await sessionStore.appendMessage(sessionID: request.sessionID, message: assistantMsg)

        // 8. Record audit (for /why)
        let auditRecord = ResponseAuditRecord(
            sessionID: request.sessionID,
            modelUsed: completion.model,
            memoryIDsUsed: memoryIDs,
            setupReportUsed: report != nil,
            permissionSummaryUsed: !permSummary.isEmpty,
            rejectedMemoriesExcluded: true,
            rawScoutRecordsExcluded: true,
            cookiesExcluded: true,
            secretsExcluded: true
        )
        // Audit-log failures must NOT block the response. Losing one audit
        // row is bad; losing the user's response because the auditor threw
        // is worse. `try?` swallows the error — the writer is responsible
        // for surfacing its own failures elsewhere if it cares.
        try? await auditLogger.logResponseAudit(auditRecord)

        // 9. Return response with metadata
        return AgentResponse(
            message: completion.content,
            sessionID: request.sessionID,
            memoryIDsUsed: memoryIDs,
            setupReportUsed: report != nil,
            permissionSummaryUsed: !permSummary.isEmpty,
            modelUsed: completion.model
        )
    }
}
