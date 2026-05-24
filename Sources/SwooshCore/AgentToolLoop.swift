// SwooshCore/AgentToolLoop.swift — 0.9S Agent tool loop
//
// The tool-calling agent loop:
// User → Prompt → Model → Tool Call → Execute → Result → Model → Final Answer
//
// Hard rules:
// - AgentKernel executes tools ONLY through ToolRegistry.
// - ToolRegistry enforces Firewall.
// - Risky tools create pending approvals.
// - humanOnly tools cannot be executed by model-origin calls.
// - The model cannot approve its own tool calls.
// - Rejected memories never enter the prompt.
// - Crypto tools must not accept private keys, seed phrases, or cookies.

import Foundation
import SwooshTools

// MARK: - Enhanced agent response with tool traces

public struct AgentToolResponse: Sendable {
    public let message: String
    public let sessionID: String
    public let memoryIDsUsed: [String]
    public let toolTracesUsed: [ToolCallTrace]
    public let setupReportUsed: Bool
    public let permissionSummaryUsed: Bool
    public let modelUsed: String
    public let toolCallCount: Int
    public let hasPendingApproval: Bool
    public let pendingApprovalID: String?
    public let createdAt: Date

    public init(
        message: String,
        sessionID: String,
        memoryIDsUsed: [String] = [],
        toolTracesUsed: [ToolCallTrace] = [],
        setupReportUsed: Bool = false,
        permissionSummaryUsed: Bool = false,
        modelUsed: String = "unknown",
        toolCallCount: Int = 0,
        hasPendingApproval: Bool = false,
        pendingApprovalID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.message = message
        self.sessionID = sessionID
        self.memoryIDsUsed = memoryIDsUsed
        self.toolTracesUsed = toolTracesUsed
        self.setupReportUsed = setupReportUsed
        self.permissionSummaryUsed = permissionSummaryUsed
        self.modelUsed = modelUsed
        self.toolCallCount = toolCallCount
        self.hasPendingApproval = hasPendingApproval
        self.pendingApprovalID = pendingApprovalID
        self.createdAt = createdAt
    }

    /// Format for /why command.
    public var whySummary: String {
        var lines: [String] = [
            "─── /why ───────────────────────────────",
            "",
            "Model: \(modelUsed)",
            "Memories used: \(memoryIDsUsed.count)",
            "Setup report used: \(setupReportUsed ? "yes" : "no")",
            "Permission summary used: \(permissionSummaryUsed ? "yes" : "no")",
            "Tool calls: \(toolCallCount)",
        ]

        if !toolTracesUsed.isEmpty {
            lines.append("")
            lines.append("Tool call traces:")
            for trace in toolTracesUsed {
                lines.append(trace.whySummary)
                lines.append("")
            }
        }

        if hasPendingApproval {
            lines.append("⏳ Pending approval: \(pendingApprovalID ?? "unknown")")
        }

        lines.append("")
        lines.append("Excluded from context: rejected candidates, raw Scout records, cookies, secrets")
        lines.append("────────────────────────────────────────")
        return lines.joined(separator: "\n")
    }

    public var agentResponse: AgentResponse {
        AgentResponse(
            message: message,
            sessionID: sessionID,
            memoryIDsUsed: memoryIDsUsed,
            setupReportUsed: setupReportUsed,
            permissionSummaryUsed: permissionSummaryUsed,
            modelUsed: modelUsed,
            createdAt: createdAt
        )
    }
}

// MARK: - Agent tool loop

/// The tool-calling agent loop. Extends AgentKernel functionality.
/// Runs model → tool → model loops with Firewall enforcement.
public actor AgentToolLoop {
    let memoryLoader: any MemoryContextLoading
    let reportLoader: any SetupReportLoading
    let permSummarizer: any PermissionSummarizing
    let sessionStore: any SessionStoring
    let auditLogger: any ResponseAuditing
    let modelProvider: any ModelProvider
    let toolRegistry: ToolRegistry
    let toolParser: ToolCallParsing
    let toolPromptBuilder: ToolPromptBuilder
    let promptBuilder: PromptBuilder
    let policy: ToolCallPolicy
    let skillCatalogProvider: SkillCatalogProviding?

    /// The most recent response's tool traces (for /why).
    var lastToolTraces: [ToolCallTrace] = []
    var lastResponse: AgentToolResponse?

    public init(
        memoryLoader: any MemoryContextLoading,
        reportLoader: any SetupReportLoading,
        permSummarizer: any PermissionSummarizing,
        sessionStore: any SessionStoring,
        auditLogger: any ResponseAuditing,
        modelProvider: any ModelProvider,
        toolRegistry: ToolRegistry,
        toolParser: ToolCallParsing = ToolCallParser(),
        toolPromptBuilder: ToolPromptBuilder = ToolPromptBuilder(),
        promptBuilder: PromptBuilder = PromptBuilder(),
        policy: ToolCallPolicy = .defaultAgent,
        skillCatalogProvider: SkillCatalogProviding? = nil
    ) {
        self.memoryLoader = memoryLoader
        self.reportLoader = reportLoader
        self.permSummarizer = permSummarizer
        self.sessionStore = sessionStore
        self.auditLogger = auditLogger
        self.modelProvider = modelProvider
        self.toolRegistry = toolRegistry
        self.toolParser = toolParser
        self.toolPromptBuilder = toolPromptBuilder
        self.promptBuilder = promptBuilder
        self.policy = policy
        self.skillCatalogProvider = skillCatalogProvider
    }

    public func loadTranscript(sessionID: String) async throws -> [ChatMessage] {
        try await sessionStore.loadTranscript(sessionID: sessionID)
    }

    // MARK: - Main entry point

    public func run(_ request: AgentRequest) async throws -> AgentToolResponse {
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
        let systemPromptResult = promptBuilder.buildSystemPrompt(
            approvedMemories: mappedMemories,
            setupReport: report,
            permissionSummary: permSummary,
            skillCatalog: mappedSkills
        )
        let basePrompt = systemPromptResult.prompt
        let memoryIDs = systemPromptResult.memoryIDs

        // 3. Get available tools
        let toolContext = ToolContext(
            sessionID: request.sessionID,
            toolPolicy: policy,
            isModelInvocation: true
        )
        let availableTools = policy.allowModelToolCalls
            ? await toolRegistry.listAvailable(context: toolContext)
            : []

        // 4. Build tool instructions
        let toolInstructions = toolPromptBuilder.buildToolInstructions(
            tools: availableTools,
            policy: policy
        )

        let systemPrompt = basePrompt + "\n\n" + toolInstructions

        // 5. Load or initialize transcript
        let storedTranscript = try await sessionStore.loadTranscript(sessionID: request.sessionID)
        let priorSystemPrompt = storedTranscript.first(where: { $0.role == .system })?.content
        var transcript = storedTranscript.filter { $0.role != .system }
        let systemMsg = ChatMessage(role: .system, content: systemPrompt)
        transcript.insert(systemMsg, at: 0)
        if priorSystemPrompt != systemPrompt {
            try await sessionStore.appendMessage(sessionID: request.sessionID, message: systemMsg)
        }

        // 6. Append user message
        let userMsg = ChatMessage(role: .user, content: request.input)
        transcript.append(userMsg)
        try await sessionStore.appendMessage(sessionID: request.sessionID, message: userMsg)

        // 7. Tool-calling loop
        var toolCallsUsed: [ToolCallTrace] = []
        var toolCallCount = 0
        var lastModel = "unknown"
        let toolLimit = policy.effectiveToolLimit

        // Snapshot factory — every call site that finishes a response
        // needs a fresh TurnContext over the current loop state. Inlined
        // 7 times before; extracted here to dedupe and shrink `run()`
        // below the 100-LOC threshold.
        let snapshot: () -> TurnContext = {
            TurnContext(
                request: request,
                memoryIDs: memoryIDs,
                toolTraces: toolCallsUsed,
                setupReportUsed: report != nil,
                permSummaryUsed: !permSummary.isEmpty,
                model: lastModel,
                toolCallCount: toolCallCount
            )
        }


        while true {
            // Enforce tool-call limit
            if policy.allowModelToolCalls && toolCallCount >= toolLimit {
                return try await finishResponse(
                    text: "I've reached the maximum number of tool calls (\(toolLimit)) for this turn. Here's what I know so far based on the tool results above.",
                    context: snapshot(),
                    transcript: &transcript
                )
            }
            // Call model
            let completionRequest = ModelCompletionRequest(
                messages: transcript,
                model: request.model,
                providerID: request.providerID,
                tools: availableTools
            )
            let completion = try await modelProvider.complete(completionRequest)
            lastModel = completion.model

            // Parse response
            let parsed = try toolParser.parse(
                response: completion,
                sessionID: request.sessionID,
                origin: .model
            )

            switch parsed {
            case .assistantText(let text):
                return try await finishResponse(
                    text: text,
                    context: snapshot(),
                    transcript: &transcript
                )

            case .toolCall(let toolRequest):
                guard policy.allowModelToolCalls else {
                    return try await finishResponse(
                        text: "Tool calls are disabled by the current runtime policy.",
                        context: snapshot(),
                        transcript: &transcript
                    )
                }
                toolCallCount += 1
                let result = await executeAndAppend(
                    toolRequest: toolRequest,
                    request: request,
                    transcript: &transcript,
                    toolCallsUsed: &toolCallsUsed
                )

                if result.status == .pendingApproval {
                    return try await finishPendingApprovalResponse(
                        toolRequest: toolRequest,
                        result: result,
                        context: snapshot(),
                        transcript: &transcript
                    )
                }

            case .multipleToolCalls(let requests):
                guard policy.allowModelToolCalls else {
                    return try await finishResponse(
                        text: "Tool calls are disabled by the current runtime policy.",
                        context: snapshot(),
                        transcript: &transcript
                    )
                }
                for toolRequest in requests {
                    toolCallCount += 1
                    if toolCallCount > toolLimit { break }

                    let result = await executeAndAppend(
                        toolRequest: toolRequest,
                        request: request,
                        transcript: &transcript,
                        toolCallsUsed: &toolCallsUsed
                    )

                    if result.status == .pendingApproval {
                        return try await finishPendingApprovalResponse(
                            toolRequest: toolRequest,
                            result: result,
                            context: snapshot(),
                            transcript: &transcript
                        )
                    }
                }
            }
        }
    }
}
