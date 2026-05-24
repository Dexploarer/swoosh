// SwooshCore/ToolPromptBuilder.swift — 0.9S Tool prompt builder
//
// Adds tool schemas and policy instructions to the system prompt.
// Only enabled/available tools are included.

import Foundation
import SwooshTools

public struct ToolPromptBuilder: Sendable {
    public init() {}

    /// Build tool instructions for the system prompt.
    public func buildToolInstructions(
        tools: [ToolDescriptor],
        policy: ToolCallPolicy
    ) -> String {
        guard policy.allowModelToolCalls && !tools.isEmpty else {
            return ""
        }

        return """
        ## Tool Calling

        You may request tools only through the provided tool-call interface.

        Rules:
        - Use tools only when they are necessary to answer the user's request.
        - Do not invent tool names. Only use tools listed below.
        - Do not invent arguments. Only use fields from the schema.
        - Do not call tools outside their schemas.
        - Do not request browser cookies, passwords, private keys, seed phrases, or unapproved files.
        - Do not approve your own memory writes.
        - Do not approve your own tool calls.
        - For blockchain actions, you may build unsigned transactions, but you may not sign or broadcast without human approval.
        - If a tool is blocked by permission or approval, explain what is needed.

        Tool-call policy:
        - Max tool calls per turn: \(policy.maxToolCallsPerTurn)
        - Max chain depth: \(policy.maxToolChainDepth)
        - Human-only tools cannot be executed by the model.

        Available tools:
        \(formatTools(tools))
        """
    }

    private func formatTools(_ tools: [ToolDescriptor]) -> String {
        tools
            .sorted { $0.name < $1.name }
            .map { tool in
                let approvalStr: String
                switch tool.approval {
                case .never:                    approvalStr = "no approval"
                case .askFirstTime:             approvalStr = "ask first time"
                case .askEveryTime:             approvalStr = "ask every time"
                case .askForRiskAtLeast(let r):  approvalStr = "ask for \(r.rawValue)+"
                case .humanOnly:                approvalStr = "human only"
                case .disabled:                 approvalStr = "disabled"
                }
                return """
                - \(tool.name)
                  Description: \(tool.description)
                  Permission: \(tool.permission.rawValue)
                  Risk: \(tool.risk.rawValue)
                  Approval: \(approvalStr)
                """
            }
            .joined(separator: "\n")
    }
}
