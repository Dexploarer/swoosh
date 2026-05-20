// SwooshCore/AgentToolLoop.swift — Agent tool loop (0.4B)
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
    private let memoryLoader: any MemoryContextLoading
    private let reportLoader: any SetupReportLoading
    private let permSummarizer: any PermissionSummarizing
    private let sessionStore: any SessionStoring
    private let auditLogger: any ResponseAuditing
    private let modelProvider: any ModelProvider
    private let toolRegistry: ToolRegistry
    private let toolParser: ToolCallParsing
    private let toolPromptBuilder: ToolPromptBuilder
    private let promptBuilder: PromptBuilder
    private let policy: ToolCallPolicy

    /// The most recent response's tool traces (for /why).
    private var lastToolTraces: [ToolCallTrace] = []
    private var lastResponse: AgentToolResponse?

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
        policy: ToolCallPolicy = .defaultAgent
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
    }

    // MARK: - Main entry point

    public func run(_ request: AgentRequest) async throws -> AgentToolResponse {
        // 1. Load approved context ONLY
        let memories = try await memoryLoader.loadApprovedMemories()
        let report = try await reportLoader.loadLatestSetupReport()
        let permSummary = try await permSummarizer.permissionSummary()

        // 2. Build system prompt (privacy boundary)
        let (basePrompt, memoryIDs) = promptBuilder.buildSystemPrompt(
            approvedMemories: memories,
            setupReport: report,
            permissionSummary: permSummary
        )

        // 3. Get available tools
        let toolContext = ToolContext(
            sessionID: request.sessionID,
            isModelInvocation: true
        )
        let availableTools = await toolRegistry.listAvailable(context: toolContext)

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

        while true {
            // Enforce tool-call limit
            if toolCallCount >= policy.maxToolCallsPerTurn {
                return try await finishResponse(
                    text: "I've reached the maximum number of tool calls (\(policy.maxToolCallsPerTurn)) for this turn. Here's what I know so far based on the tool results above.",
                    request: request,
                    memoryIDs: memoryIDs,
                    toolTraces: toolCallsUsed,
                    setupReportUsed: report != nil,
                    permSummaryUsed: !permSummary.isEmpty,
                    model: lastModel,
                    toolCallCount: toolCallCount,
                    transcript: &transcript
                )
            }
            // Call model
            let completionRequest = ModelCompletionRequest(messages: transcript, tools: availableTools)
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
                    request: request,
                    memoryIDs: memoryIDs,
                    toolTraces: toolCallsUsed,
                    setupReportUsed: report != nil,
                    permSummaryUsed: !permSummary.isEmpty,
                    model: lastModel,
                    toolCallCount: toolCallCount,
                    transcript: &transcript
                )

            case .toolCall(let toolRequest):
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
                        request: request,
                        memoryIDs: memoryIDs,
                        toolTraces: toolCallsUsed,
                        setupReportUsed: report != nil,
                        permSummaryUsed: !permSummary.isEmpty,
                        model: lastModel,
                        toolCallCount: toolCallCount,
                        transcript: &transcript
                    )
                }

            case .multipleToolCalls(let requests):
                for toolRequest in requests {
                    toolCallCount += 1
                    if toolCallCount > policy.maxToolCallsPerTurn { break }

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
                            request: request,
                            memoryIDs: memoryIDs,
                            toolTraces: toolCallsUsed,
                            setupReportUsed: report != nil,
                            permSummaryUsed: !permSummary.isEmpty,
                            model: lastModel,
                            toolCallCount: toolCallCount,
                            transcript: &transcript
                        )
                    }
                }
            }
        }
    }

    private func finishPendingApprovalResponse(
        toolRequest: ToolExecutionRequest,
        result: ToolExecutionResult,
        request: AgentRequest,
        memoryIDs: [String],
        toolTraces: [ToolCallTrace],
        setupReportUsed: Bool,
        permSummaryUsed: Bool,
        model: String,
        toolCallCount: Int,
        transcript: inout [ChatMessage]
    ) async throws -> AgentToolResponse {
        let finalText = """
        I need your approval before continuing.

        Tool requested: \(toolRequest.toolName)
        Approval ID: \(result.approvalID ?? "unknown")

        Use `/approve \(result.approvalID ?? "<id>")` or `/deny \(result.approvalID ?? "<id>")`.
        """
        return try await finishResponse(
            text: finalText,
            request: request,
            memoryIDs: memoryIDs,
            toolTraces: toolTraces,
            setupReportUsed: setupReportUsed,
            permSummaryUsed: permSummaryUsed,
            model: model,
            toolCallCount: toolCallCount,
            transcript: &transcript,
            hasPendingApproval: true,
            pendingApprovalID: result.approvalID
        )
    }

    // MARK: - Execute and append

    private func executeAndAppend(
        toolRequest: ToolExecutionRequest,
        request: AgentRequest,
        transcript: inout [ChatMessage],
        toolCallsUsed: inout [ToolCallTrace]
    ) async -> ToolExecutionResult {
        let toolContext = ToolContext(
            sessionID: request.sessionID,
            isModelInvocation: toolRequest.origin.isModelInvocation
        )
        let result = await toolRegistry.execute(
            request: toolRequest,
            context: toolContext
        )

        // Append result as tool message
        let toolMessage = ChatMessage(
            role: .tool,
            content: ToolResultFormatter.format(result)
        )
        transcript.append(toolMessage)
        try? await sessionStore.appendMessage(sessionID: request.sessionID, message: toolMessage)

        // Track trace
        if let trace = result.trace {
            toolCallsUsed.append(trace)
        }

        return result
    }

    // MARK: - Finish and persist

    private func finishResponse(
        text: String,
        request: AgentRequest,
        memoryIDs: [String],
        toolTraces: [ToolCallTrace],
        setupReportUsed: Bool,
        permSummaryUsed: Bool,
        model: String,
        toolCallCount: Int,
        transcript: inout [ChatMessage],
        hasPendingApproval: Bool = false,
        pendingApprovalID: String? = nil
    ) async throws -> AgentToolResponse {
        // Persist assistant message
        let assistantMsg = ChatMessage(role: .assistant, content: text)
        transcript.append(assistantMsg)
        try await sessionStore.appendMessage(sessionID: request.sessionID, message: assistantMsg)

        // Record audit
        let auditRecord = ResponseAuditRecord(
            sessionID: request.sessionID,
            modelUsed: model,
            memoryIDsUsed: memoryIDs,
            setupReportUsed: setupReportUsed,
            permissionSummaryUsed: permSummaryUsed
        )
        try await auditLogger.logResponseAudit(auditRecord)

        let response = AgentToolResponse(
            message: text,
            sessionID: request.sessionID,
            memoryIDsUsed: memoryIDs,
            toolTracesUsed: toolTraces,
            setupReportUsed: setupReportUsed,
            permissionSummaryUsed: permSummaryUsed,
            modelUsed: model,
            toolCallCount: toolCallCount,
            hasPendingApproval: hasPendingApproval,
            pendingApprovalID: pendingApprovalID
        )

        self.lastToolTraces = toolTraces
        self.lastResponse = response

        return response
    }

    // MARK: - /why support

    public func getLastResponse() -> AgentToolResponse? {
        lastResponse
    }

    public func getLastToolTraces() -> [ToolCallTrace] {
        lastToolTraces
    }
}
