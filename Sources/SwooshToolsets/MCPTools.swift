// SwooshToolsets/MCPTools.swift — Agent-facing MCP tools
//
// Three static tools wire the SwooshMCP module into the agent's
// ToolRegistry:
//
//   • mcp.list_servers — read-only; returns the configured server
//     profiles (id, name, enabled, trust, state).
//   • mcp.list_tools   — read-only; returns discovered tools for a
//     server (name, title, description, inputSchemaJSON,
//     estimatedRisk via MCPServerRegistry.classifyToolRisk).
//   • mcp.call         — high-risk, askEveryTime; opens an MCPClient,
//     handshakes, invokes the tool, redacts + truncates the result
//     via MCPServerRegistry, then disconnects.
//
// Safety contract (preserved):
//   • Imported MCP tools stay UNTRUSTED. `mcp.call`'s static
//     `ToolRisk.high` + `ApprovalPolicy.askEveryTime` guarantees the
//     registry's existing approval gate fires once per call regardless
//     of how the MCP server classifies its own tool. (See the wiring
//     plan / advisor option 2.)
//   • Trust mutations (`addServer` / `enableServer` / `disableServer` /
//     `removeServer` / `allowTool` / `denyTool`) are NEVER registered
//     as tools — those flows belong to the CLI, not the agent.
//   • The server must be `enabled` AND the underlying tool name must
//     pass `MCPToolPolicy.isAllowed` before `mcp.call` will dial.
//   • Result text is run through `MCPServerRegistry.redactResult` and
//     capped at `MCPToolPolicy.maxResultBytes`.
//   • Every call goes through ToolRegistry → Firewall → ApprovalCenter
//     like every other tool. The MCP module's own audit log is bridged
//     into the main `AuditLogging` channel via the injected `audit`
//     dependency so `/why` sees MCP activity.

import Foundation
import SwooshTools
import SwooshMCP

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP dependencies
// ═══════════════════════════════════════════════════════════════════

/// Bundle of MCP runtime collaborators consumed by the MCP tools.
///
/// Defined in `SwooshToolsets` (not `SwooshTools`) on purpose —
/// `ToolDependencies` lives below `SwooshMCP` in the module DAG, so a
/// `MCPServerRegistry` reference inside `ToolDependencies` would create
/// an import cycle. Passing `MCPDependencies` as a separate parameter to
/// `DefaultToolRegistrar.registerAll` mirrors the `SelfImprovementDependencies`
/// pattern and keeps the lower layers ignorant of MCP.
public struct MCPDependencies: Sendable {
    public let registry: MCPServerRegistry
    public let connector: MCPConnector

    public init(registry: MCPServerRegistry, connector: MCPConnector) {
        self.registry = registry
        self.connector = connector
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - mcp.list_servers
// ═══════════════════════════════════════════════════════════════════

public struct MCPListServersInput: Codable, Sendable {
    public init() {}
}

public struct MCPListServersOutput: Codable, Sendable {
    public struct ServerSummary: Codable, Sendable {
        public let id: String
        public let name: String
        public let description: String?
        public let enabled: Bool
        public let trustLevel: String
        public let state: String
        public let transport: String
    }
    public let servers: [ServerSummary]

    public init(servers: [ServerSummary]) { self.servers = servers }
}

public struct MCPListServersTool: SwooshTool {
    public typealias Input = MCPListServersInput
    public typealias Output = MCPListServersOutput
    public static let name: ToolName = "mcp.list_servers"
    public static let displayName = "List MCP Servers"
    public static let description = "List configured MCP servers and their enabled/trust state."
    public static let permission = SwooshPermission.mcpRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.mcp

    let mcp: MCPDependencies
    public init(mcp: MCPDependencies) { self.mcp = mcp }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let profiles = await mcp.registry.listServers()
        let summaries = profiles.map { p in
            MCPListServersOutput.ServerSummary(
                id: p.id,
                name: p.name,
                description: p.description,
                enabled: p.enabled,
                trustLevel: p.trustLevel.rawValue,
                state: p.state.rawValue,
                transport: Self.transportLabel(p.transport)
            )
        }
        return MCPListServersOutput(servers: summaries)
    }

    private static func transportLabel(_ transport: MCPTransportConfiguration) -> String {
        switch transport {
        case .stdio: return "stdio"
        case .http:  return "http"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - mcp.list_tools
// ═══════════════════════════════════════════════════════════════════

public struct MCPListToolsInput: Codable, Sendable {
    public let serverID: String
    public init(serverID: String) { self.serverID = serverID }
}

public struct MCPListToolsOutput: Codable, Sendable {
    public struct ToolEntry: Codable, Sendable {
        public let name: String
        public let title: String?
        public let description: String?
        /// Full JSON Schema string the MCP server advertised for this
        /// tool's input. Use it to construct valid `arguments` for
        /// `mcp.call`.
        public let inputSchemaJSON: String?
        /// Heuristic risk classification (`MCPServerRegistry.classifyToolRisk`).
        /// Informational only — the actual approval gate is the static
        /// `mcp.call.high`.
        public let estimatedRisk: String
    }
    public let serverID: String
    public let tools: [ToolEntry]

    public init(serverID: String, tools: [ToolEntry]) {
        self.serverID = serverID
        self.tools = tools
    }
}

public struct MCPListToolsTool: SwooshTool {
    public typealias Input = MCPListToolsInput
    public typealias Output = MCPListToolsOutput
    public static let name: ToolName = "mcp.list_tools"
    public static let displayName = "List MCP Tools"
    public static let description =
        "List the tools discovered from a configured MCP server, including their JSON-Schema inputs."
    public static let permission = SwooshPermission.mcpRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.mcp

    let mcp: MCPDependencies
    public init(mcp: MCPDependencies) { self.mcp = mcp }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard await mcp.registry.getServer(input.serverID) != nil else {
            throw ToolError.executionFailed("Unknown MCP server '\(input.serverID)'")
        }
        let discovered = await mcp.registry.listTools(serverID: input.serverID)
        var entries: [MCPListToolsOutput.ToolEntry] = []
        entries.reserveCapacity(discovered.count)
        for tool in discovered {
            let risk = await mcp.registry.classifyToolRisk(
                serverID: input.serverID,
                toolName: tool.name
            )
            entries.append(MCPListToolsOutput.ToolEntry(
                name: tool.name,
                title: tool.title,
                description: tool.description,
                inputSchemaJSON: tool.inputSchemaJSON,
                estimatedRisk: risk.rawValue
            ))
        }
        return MCPListToolsOutput(serverID: input.serverID, tools: entries)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - mcp.call
// ═══════════════════════════════════════════════════════════════════

public struct MCPCallInput: Codable, Sendable {
    public let serverID: String
    public let toolName: String
    /// Arguments to pass to the MCP tool. Must conform to the server's
    /// advertised `inputSchemaJSON` (see `mcp.list_tools`). Defaults to
    /// an empty object so tools with no required args can be called
    /// without explicit arguments.
    public let arguments: JSONValue

    public init(serverID: String, toolName: String, arguments: JSONValue = .object([:])) {
        self.serverID = serverID
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct MCPCallOutput: Codable, Sendable {
    /// Result text, after `MCPContentRedactor.redact` and a hard byte cap
    /// at `MCPToolPolicy.maxResultBytes`.
    public let text: String
    /// `true` when the MCP server flagged the call as an error result.
    public let isError: Bool
    /// Server ID + tool name echoed back so the agent can attribute the
    /// output without tracking the request.
    public let serverID: String
    public let toolName: String

    public init(text: String, isError: Bool, serverID: String, toolName: String) {
        self.text = text
        self.isError = isError
        self.serverID = serverID
        self.toolName = toolName
    }
}

public struct MCPCallTool: SwooshTool {
    public typealias Input = MCPCallInput
    public typealias Output = MCPCallOutput
    public static let name: ToolName = "mcp.call"
    public static let displayName = "Call MCP Tool"
    public static let description = """
    Execute a discovered tool on a configured MCP server. Imported tools \
    are UNTRUSTED — every call requires explicit user approval, the \
    result is redacted for secrets, and the output is truncated to the \
    server's configured maxResultBytes before return.
    """
    public static let permission = SwooshPermission.mcpExecute
    /// Static high risk by design: the underlying MCP tool could be
    /// anything, and `MCPServerProfile.trustLevel` defaults to `.untrusted`.
    /// Setting this lower would let "destructive" MCP tools slip through
    /// at a medium gate. The registry's approval pipeline turns this into
    /// an always-prompt UX.
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.mcp

    let mcp: MCPDependencies
    let audit: any AuditLogging
    public init(mcp: MCPDependencies, audit: any AuditLogging) {
        self.mcp = mcp
        self.audit = audit
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        // ── Server + policy gate ──────────────────────────────────
        guard let profile = await mcp.registry.getServer(input.serverID) else {
            throw ToolError.executionFailed("Unknown MCP server '\(input.serverID)'")
        }
        guard profile.enabled else {
            throw ToolError.executionFailed("MCP server '\(input.serverID)' is disabled")
        }
        guard profile.toolPolicy.isAllowed(input.toolName) else {
            throw ToolError.executionFailed(
                "MCP tool '\(input.toolName)' is denied or not on the allowlist for server '\(input.serverID)'"
            )
        }

        // ── Bridge audit-start into the main AuditLogging channel ─
        let qualifiedName = "mcp.\(input.serverID).\(input.toolName)"
        try? await audit.append(AuditEntry(
            kind: .toolCallStarted,
            toolName: qualifiedName,
            sessionID: context.sessionID,
            detail: "MCP call → \(input.serverID)/\(input.toolName)"
        ))

        // ── Connect + handshake + call + disconnect ───────────────
        #if os(macOS) || os(Linux)
        let client: MCPClient
        do {
            client = try await mcp.connector.makeClient(for: profile)
        } catch {
            try? await audit.append(AuditEntry(
                kind: .toolCallFailed,
                toolName: qualifiedName,
                sessionID: context.sessionID,
                detail: "MCP connector failed: \(error.localizedDescription)",
                success: false
            ))
            throw ToolError.executionFailed("MCP connector failed: \(error.localizedDescription)")
        }

        do {
            try await client.connect()
            _ = try await client.initialize()
            let argsMap = Self.convertArgs(input.arguments)
            let result = try await client.callTool(name: input.toolName, arguments: argsMap)
            await client.disconnect()

            // ── Redact + truncate ─────────────────────────────────
            let redacted = await mcp.registry.redactResult(result.text)
            let cap = profile.toolPolicy.maxResultBytes
            let capped: String
            if redacted.utf8.count > cap {
                capped = String(redacted.prefix(cap)) + "\n… (output truncated at \(cap) bytes)"
            } else {
                capped = redacted
            }

            try? await audit.append(AuditEntry(
                kind: .toolCallSucceeded,
                toolName: qualifiedName,
                sessionID: context.sessionID,
                detail: "MCP call completed (isError=\(result.isError), \(capped.utf8.count) bytes)"
            ))

            return MCPCallOutput(
                text: capped,
                isError: result.isError,
                serverID: input.serverID,
                toolName: input.toolName
            )
        } catch {
            await client.disconnect()
            try? await audit.append(AuditEntry(
                kind: .toolCallFailed,
                toolName: qualifiedName,
                sessionID: context.sessionID,
                detail: "MCP call failed: \(error.localizedDescription)",
                success: false
            ))
            throw ToolError.executionFailed("MCP call failed: \(error.localizedDescription)")
        }
        #else
        // iOS / non-desktop: MCPConnector.makeClient is gated to
        // macOS/Linux because it spawns a child process. The iOS
        // companion app talks to the daemon for MCP work; there is no
        // legitimate caller for this branch.
        try? await audit.append(AuditEntry(
            kind: .toolCallFailed,
            toolName: qualifiedName,
            sessionID: context.sessionID,
            detail: "MCP stdio calls require macOS or Linux",
            success: false
        ))
        throw ToolError.executionFailed("MCP stdio calls require macOS or Linux")
        #endif
    }

    /// Convert the agent-facing `JSONValue` argument tree into the
    /// `JSONRPCValue` shape the MCP client expects on the wire. The two
    /// enums are structurally identical; this is a pure transcoding pass
    /// at module boundary.
    static func convertArgs(_ value: JSONValue) -> [String: JSONRPCValue] {
        guard case .object(let dict) = value else { return [:] }
        var out: [String: JSONRPCValue] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict { out[k] = convert(v) }
        return out
    }

    private static func convert(_ value: JSONValue) -> JSONRPCValue {
        switch value {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .string(let s): return .string(s)
        case .array(let arr): return .array(arr.map(convert))
        case .object(let dict):
            var out: [String: JSONRPCValue] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict { out[k] = convert(v) }
            return .object(out)
        }
    }
}
