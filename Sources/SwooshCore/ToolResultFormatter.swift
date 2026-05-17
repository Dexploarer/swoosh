// SwooshCore/ToolResultFormatter.swift — Tool result formatter (0.4B)
//
// Formats tool execution results for the model transcript.
// Compact. Model should not receive giant logs.

import Foundation
import SwooshTools

public struct ToolResultFormatter: Sendable {

    public init() {}

    public static func format(_ result: ToolExecutionResult) -> String {
        switch result.status {
        case .succeeded:
            let outputStr = result.output?.compactJSONString(maxBytes: 8_000) ?? "null"
            return """
            Tool result:
            - tool: \(result.toolName)
            - status: succeeded
            - output:
            \(outputStr)
            """

        case .pendingApproval:
            return """
            Tool result:
            - tool: \(result.toolName)
            - status: pending_approval
            - approval_id: \(result.approvalID ?? "unknown")
            - message: This tool requires approval before it can be executed.
            """

        case .blockedByPermission:
            return """
            Tool result:
            - tool: \(result.toolName)
            - status: blocked_by_permission
            - error: \(result.errorMessage ?? "Permission denied.")
            """

        case .deniedByUser:
            return """
            Tool result:
            - tool: \(result.toolName)
            - status: denied_by_user
            - error: \(result.errorMessage ?? "User denied the tool call.")
            """

        case .disabled:
            return """
            Tool result:
            - tool: \(result.toolName)
            - status: disabled
            - error: \(result.errorMessage ?? "This tool is disabled.")
            """

        case .failed:
            return """
            Tool result:
            - tool: \(result.toolName)
            - status: failed
            - error: \(result.errorMessage ?? "Unknown error.")
            """
        }
    }
}

// MARK: - JSONValue compact string

extension JSONValue {
    /// Returns a compact JSON string representation, truncated to maxBytes.
    public func compactJSONString(maxBytes: Int = 8_000) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "<unserializable>"
        }
        if text.utf8.count > maxBytes {
            let truncated = String(text.prefix(maxBytes))
            return truncated + "...(truncated)"
        }
        return text
    }
}
