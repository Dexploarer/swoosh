// SwooshTools/ToolCallTrace.swift — Tool-call trace (0.4B)
//
// The trace is the complete record of a tool-call lifecycle.
// Used by /why to explain what happened.

import Foundation

public struct ToolCallTrace: Codable, Sendable, Identifiable {
    public let id: String
    public let sessionID: String
    public let requestID: String
    public let toolName: String
    public let origin: ToolCallOrigin
    public let risk: ToolRisk
    public let permission: SwooshPermission
    public let approvalPolicy: ApprovalPolicy
    public let status: ToolExecutionStatus
    public let startedAt: Date
    public let finishedAt: Date?
    public let inputPreview: String
    public let outputPreview: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        requestID: String,
        toolName: String,
        origin: ToolCallOrigin,
        risk: ToolRisk,
        permission: SwooshPermission,
        approvalPolicy: ApprovalPolicy,
        status: ToolExecutionStatus,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        inputPreview: String,
        outputPreview: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.requestID = requestID
        self.toolName = toolName
        self.origin = origin
        self.risk = risk
        self.permission = permission
        self.approvalPolicy = approvalPolicy
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.inputPreview = inputPreview
        self.outputPreview = outputPreview
    }
}

// MARK: - Human-readable formatting for /why

extension ToolCallTrace {
    public var whySummary: String {
        let statusEmoji: String
        switch status {
        case .succeeded:           statusEmoji = "✅"
        case .failed:              statusEmoji = "❌"
        case .blockedByPermission: statusEmoji = "🚫"
        case .pendingApproval:     statusEmoji = "⏳"
        case .deniedByUser:        statusEmoji = "🚷"
        case .disabled:            statusEmoji = "⛔"
        }

        var lines = [
            "\(statusEmoji) \(toolName)",
            "   Origin: \(origin.rawValue)",
            "   Risk: \(risk.rawValue)",
            "   Permission: \(permission.rawValue)",
            "   Approval: \(approvalPolicy)",
            "   Status: \(status.rawValue)",
        ]
        if !inputPreview.isEmpty {
            lines.append("   Input: \(inputPreview.prefix(120))")
        }
        if let out = outputPreview {
            lines.append("   Output: \(out.prefix(120))")
        }
        if let fin = finishedAt {
            let duration = fin.timeIntervalSince(startedAt)
            lines.append("   Duration: \(String(format: "%.2f", duration))s")
        }
        return lines.joined(separator: "\n")
    }
}
