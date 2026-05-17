// SwooshTUI/ToolCommands.swift — /tools, /tool, /approvals, /approve, /deny (0.4B)
//
// Slash commands for tool discovery, manual execution, and approval management.
// All commands go through ToolRegistry → Firewall → ApprovalCenter → Audit.

import Foundation

// MARK: - Tool command definitions

/// Creates tool-related slash command definitions for 0.4B.
/// These commands require access to the ToolRegistry and ApprovalCenter at registration time.
public struct ToolCommandFactory {

    public init() {}

    // MARK: - /tools

    /// `/tools` — list available tools with risk and approval policy.
    /// `/tools enabled` — only show enabled tools.
    /// `/tools schema <name>` — show full schema for a tool.
    /// `/tools risk <risk>` — filter by risk level.
    /// `/tools toolset <toolset>` — filter by toolset.
    public func makeToolsCommand(
        listTools: @escaping @Sendable (ToolsFilter) async -> String
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            name: "tools",
            summary: "List available tools, schemas, and policies",
            usage: "/tools [enabled|schema <name>|risk <level>|toolset <name>]",
            category: .agent
        ) { ctx in
            let filter = ToolsFilter.parse(ctx.arguments)
            let output = await listTools(filter)
            return .success(output)
        }
    }

    // MARK: - /tool

    /// `/tool <tool-name> <json-arguments>` — manually execute a tool as human origin.
    public func makeToolCommand(
        executeTool: @escaping @Sendable (String, String, String) async -> String
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            name: "tool",
            summary: "Manually execute a tool (human origin)",
            usage: "/tool <tool-name> <json-arguments>",
            category: .agent
        ) { ctx in
            guard !ctx.arguments.isEmpty else {
                return .error("Usage: /tool <tool-name> <json-arguments>")
            }
            let toolName = ctx.arguments[0]
            let argsJSON = ctx.arguments.count > 1
                ? ctx.arguments.dropFirst().joined(separator: " ")
                : "{}"
            let output = await executeTool(toolName, argsJSON, ctx.sessionID)
            return .success(output)
        }
    }

    // MARK: - /approvals

    /// `/approvals` — list pending approval requests.
    public func makeApprovalsCommand(
        listApprovals: @escaping @Sendable (String) async -> String
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            name: "approvals",
            summary: "List pending approval requests",
            usage: "/approvals",
            category: .agent
        ) { ctx in
            let output = await listApprovals(ctx.sessionID)
            return .success(output)
        }
    }

    // MARK: - /approve

    /// `/approve <id>` — approve a pending tool call.
    /// `/approve <id> once` — approve for this call only.
    /// `/approve <id> session` — approve for the rest of this session.
    public func makeApproveCommand(
        approve: @escaping @Sendable (String, String, String) async -> String
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            name: "approve",
            summary: "Approve a pending tool call",
            usage: "/approve <id> [once|session]",
            category: .agent
        ) { ctx in
            guard let approvalID = ctx.arguments.first else {
                return .error("Usage: /approve <approval-id> [once|session]")
            }
            let scope = ctx.arguments.count > 1 ? ctx.arguments[1] : "once"
            let output = await approve(approvalID, scope, ctx.sessionID)
            return .success(output)
        }
    }

    // MARK: - /deny

    /// `/deny <id>` — deny a pending tool call.
    /// `/deny <id> "reason"` — deny with a reason.
    public func makeDenyCommand(
        deny: @escaping @Sendable (String, String?, String) async -> String
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            name: "deny",
            summary: "Deny a pending tool call",
            usage: "/deny <id> [\"reason\"]",
            category: .agent
        ) { ctx in
            guard let approvalID = ctx.arguments.first else {
                return .error("Usage: /deny <approval-id> [\"reason\"]")
            }
            let reason = ctx.arguments.count > 1
                ? ctx.arguments.dropFirst().joined(separator: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                : nil
            let output = await deny(approvalID, reason, ctx.sessionID)
            return .success(output)
        }
    }

    // MARK: - /why

    /// `/why` — explain what tools, memories, permissions, and approvals were used.
    public func makeWhyCommand(
        getWhySummary: @escaping @Sendable (String) async -> String
    ) -> SlashCommandDefinition {
        SlashCommandDefinition(
            name: "why",
            aliases: ["explain"],
            summary: "Explain tools, memories, permissions, and approvals used in last response",
            usage: "/why",
            category: .agent
        ) { ctx in
            let output = await getWhySummary(ctx.sessionID)
            return .success(output)
        }
    }
}

// MARK: - Tools filter

public enum ToolsFilter: Sendable {
    case all
    case enabled
    case schema(String)
    case risk(String)
    case toolset(String)

    public static func parse(_ args: [String]) -> ToolsFilter {
        guard let first = args.first else { return .all }
        switch first.lowercased() {
        case "enabled":
            return .enabled
        case "schema":
            return args.count > 1 ? .schema(args[1]) : .all
        case "risk":
            return args.count > 1 ? .risk(args[1]) : .all
        case "toolset":
            return args.count > 1 ? .toolset(args[1]) : .all
        default:
            return .all
        }
    }
}
