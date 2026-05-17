// SwooshTools/ToolExecutionResult.swift — Tool execution result (0.4B)
//
// The outcome of a tool execution attempt.
// Captures success, failure, blocked, pending, denied, or disabled.

import Foundation

// MARK: - Execution status

public enum ToolExecutionStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case blockedByPermission
    case pendingApproval
    case deniedByUser
    case disabled
}

// MARK: - Execution result

public struct ToolExecutionResult: Codable, Sendable, Identifiable {
    public let id: String
    public let requestID: String
    public let toolName: String
    public let status: ToolExecutionStatus
    public let output: JSONValue?
    public let errorMessage: String?
    public let approvalID: String?
    public let trace: ToolCallTrace?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        requestID: String,
        toolName: String,
        status: ToolExecutionStatus,
        output: JSONValue? = nil,
        errorMessage: String? = nil,
        approvalID: String? = nil,
        trace: ToolCallTrace? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.requestID = requestID
        self.toolName = toolName
        self.status = status
        self.output = output
        self.errorMessage = errorMessage
        self.approvalID = approvalID
        self.trace = trace
        self.createdAt = createdAt
    }
}
