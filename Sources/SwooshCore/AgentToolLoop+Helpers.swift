// SwooshCore/AgentToolLoop+Helpers.swift — 0.9T Tool-loop helper methods
//
// Extracted from AgentToolLoop.swift in 0.9S to drop the main file
// below the 400 LOC ceiling. 0.9T tightens the helper signatures by
// bundling the per-turn audit fields (memoryIDs, setupReportUsed,
// permSummaryUsed, model, toolCallCount, transcript) into a
// `TurnContext` struct so each helper takes ≤5 parameters — silences
// SwiftLint `function_parameter_count` and Lizard `parameter-count`.
//
// Marked `extension AgentToolLoop` so the helpers stay inside the
// actor's isolation domain (they were `private` instance methods
// before; same semantics, different file).

import Foundation
import SwooshTools

extension AgentToolLoop {

    /// Bundles the audit + transcript state threaded through every
    /// helper. Built once per `run(_:)` turn and passed by value
    /// (transcript is mutated via `&transcript` at the call site,
    /// kept out of the struct so `inout` still works).
    struct TurnContext {
        let request: AgentRequest
        let memoryIDs: [String]
        let toolTraces: [ToolCallTrace]
        let setupReportUsed: Bool
        let permSummaryUsed: Bool
        let model: String
        let toolCallCount: Int
    }

    func finishPendingApprovalResponse(
        toolRequest: ToolExecutionRequest,
        result: ToolExecutionResult,
        context: TurnContext,
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
            context: context,
            transcript: &transcript,
            hasPendingApproval: true,
            pendingApprovalID: result.approvalID
        )
    }

    // MARK: - Execute and append

    func executeAndAppend(
        toolRequest: ToolExecutionRequest,
        request: AgentRequest,
        transcript: inout [ChatMessage],
        toolCallsUsed: inout [ToolCallTrace]
    ) async -> ToolExecutionResult {
        let toolContext = ToolContext(
            sessionID: request.sessionID,
            toolPolicy: policy,
            isModelInvocation: toolRequest.origin.isModelInvocation
        )
        let result = await toolRegistry.execute(
            request: toolRequest,
            context: toolContext
        )

        let toolMessage = ChatMessage(
            role: .tool,
            content: ToolResultFormatter.format(result)
        )
        transcript.append(toolMessage)
        try? await sessionStore.appendMessage(sessionID: request.sessionID, message: toolMessage)

        if let trace = result.trace {
            toolCallsUsed.append(trace)
        }

        return result
    }

    // MARK: - Finish and persist

    func finishResponse(
        text: String,
        context: TurnContext,
        transcript: inout [ChatMessage],
        hasPendingApproval: Bool = false,
        pendingApprovalID: String? = nil
    ) async throws -> AgentToolResponse {
        let assistantMsg = ChatMessage(role: .assistant, content: text)
        transcript.append(assistantMsg)
        try await sessionStore.appendMessage(sessionID: context.request.sessionID, message: assistantMsg)

        let auditRecord = ResponseAuditRecord(
            sessionID: context.request.sessionID,
            modelUsed: context.model,
            memoryIDsUsed: context.memoryIDs,
            setupReportUsed: context.setupReportUsed,
            permissionSummaryUsed: context.permSummaryUsed
        )
        try await auditLogger.logResponseAudit(auditRecord)

        let response = AgentToolResponse(
            message: text,
            sessionID: context.request.sessionID,
            memoryIDsUsed: context.memoryIDs,
            toolTracesUsed: context.toolTraces,
            setupReportUsed: context.setupReportUsed,
            permissionSummaryUsed: context.permSummaryUsed,
            modelUsed: context.model,
            toolCallCount: context.toolCallCount,
            hasPendingApproval: hasPendingApproval,
            pendingApprovalID: pendingApprovalID
        )

        self.lastToolTraces = context.toolTraces
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
