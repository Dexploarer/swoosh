// SwooshCore/AgentToolLoop+Helpers.swift — 0.9S Tool-loop helper methods
//
// Extracted from AgentToolLoop.swift in 0.9S to drop the main file
// below the 400 LOC ceiling. The helpers are not part of the public
// surface; they cooperate with the actor's `run(_:)` entry point to
// finish responses, execute individual tool calls, and surface
// pending-approval state to the caller.
//
// Marked `extension AgentToolLoop` so the helpers stay inside the
// actor's isolation domain (they were `private` instance methods
// before; same semantics, different file).

import Foundation
import SwooshTools

extension AgentToolLoop {

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
        toolPolicy: policy,
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
