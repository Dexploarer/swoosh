// SwooshTools/ToolCallOrigin.swift — Tool-call origin (0.4B)
//
// The origin of a tool call determines what is allowed.
// human-origin calls can execute humanOnly tools.
// model-origin calls cannot approve their own tool calls.

import Foundation

// MARK: - Tool-call origin

public enum ToolCallOrigin: String, Codable, Sendable {
    case model
    case human
    case workflow
    case system
}

public extension ToolCallOrigin {
    /// Whether this origin can resolve humanOnly approvals.
    var canResolveHumanOnlyApproval: Bool {
        switch self {
        case .human:
            return true
        case .model, .workflow, .system:
            return false
        }
    }

    /// Whether this origin should be treated as model invocation in ToolContext.
    var isModelInvocation: Bool {
        switch self {
        case .model:
            return true
        case .human, .workflow, .system:
            return false
        }
    }
}
