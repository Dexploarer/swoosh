// SwooshTools/ToolCallPolicy.swift — Tool-call policy (0.4B)
//
// Controls how the agent runtime may use tools.
// Enforced by AgentToolLoop.

import Foundation

public struct ToolCallPolicy: Codable, Sendable {
    public let maxToolCallsPerTurn: Int
    public let maxToolChainDepth: Int
    public let allowModelToolCalls: Bool
    public let allowHumanOnlyFromModel: Bool
    public let allowCriticalToolsFromModel: Bool
    public let requireApprovalForMediumRiskAndAbove: Bool

    public init(
        maxToolCallsPerTurn: Int = 8,
        maxToolChainDepth: Int = 4,
        allowModelToolCalls: Bool = true,
        allowHumanOnlyFromModel: Bool = false,
        allowCriticalToolsFromModel: Bool = false,
        requireApprovalForMediumRiskAndAbove: Bool = true
    ) {
        self.maxToolCallsPerTurn = maxToolCallsPerTurn
        self.maxToolChainDepth = maxToolChainDepth
        self.allowModelToolCalls = allowModelToolCalls
        self.allowHumanOnlyFromModel = allowHumanOnlyFromModel
        self.allowCriticalToolsFromModel = allowCriticalToolsFromModel
        self.requireApprovalForMediumRiskAndAbove = requireApprovalForMediumRiskAndAbove
    }

    /// Default agent policy for 0.4B.
    /// Model may call read-only tools. Model may request medium/high-risk tools.
    /// Model may not approve humanOnly tools. Model may not sign/broadcast blockchain txs.
    public static let defaultAgent = ToolCallPolicy(
        maxToolCallsPerTurn: 8,
        maxToolChainDepth: 4,
        allowModelToolCalls: true,
        allowHumanOnlyFromModel: false,
        allowCriticalToolsFromModel: false,
        requireApprovalForMediumRiskAndAbove: true
    )

    /// Restrictive policy for minimal-trust contexts.
    public static let restrictive = ToolCallPolicy(
        maxToolCallsPerTurn: 2,
        maxToolChainDepth: 1,
        allowModelToolCalls: true,
        allowHumanOnlyFromModel: false,
        allowCriticalToolsFromModel: false,
        requireApprovalForMediumRiskAndAbove: true
    )

    /// No tool calls allowed.
    public static let noTools = ToolCallPolicy(
        maxToolCallsPerTurn: 0,
        maxToolChainDepth: 0,
        allowModelToolCalls: false,
        allowHumanOnlyFromModel: false,
        allowCriticalToolsFromModel: false,
        requireApprovalForMediumRiskAndAbove: true
    )
}
