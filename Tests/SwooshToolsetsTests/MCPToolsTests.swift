// Tests/SwooshToolsetsTests/MCPToolsTests.swift
//
// Tests for the three agent-facing MCP tools wired into ToolRegistry.
// Focus is the policy/gate behavior + tool descriptor metadata + argument
// conversion. The transport-level flow (`MCPClient.connect / initialize /
// callTool`) is covered by `SwooshMCPTests`; here we only verify that
// `MCPCallTool` correctly refuses to dial when the server/tool/policy
// rejects the request.

import Testing
import Foundation
@testable import SwooshToolsets
@testable import SwooshTools
@testable import SwooshMCP
@testable import SwooshFirewall

// ═══════════════════════════════════════════════════════════════════
// MARK: - Test helpers
// ═══════════════════════════════════════════════════════════════════

private actor MockAudit: AuditLogging {
    var entries: [AuditEntry] = []
    func append(_ event: AuditEntry) async throws { entries.append(event) }
    func tail(limit: Int) async -> [AuditEntry] { Array(entries.suffix(limit)) }
    func search(query: String, limit: Int) async -> [AuditEntry] {
        entries.filter { $0.detail.contains(query) }
    }
    func getEvent(id: String) async -> AuditEntry? { entries.first { $0.id == id } }
}

private func makeContext(sessionID: String = "test-session") -> ToolContext {
    ToolContext(sessionID: sessionID, isModelInvocation: true)
}

private func stdioProfile(
    id: String,
    enabled: Bool = true,
    allowlist: [String] = [],
    denylist: [String] = []
) -> MCPServerProfile {
    var policy = MCPToolPolicy.safeDefault
    policy.allowlist = allowlist
    policy.denylist = denylist
    return MCPServerProfile(
        id: id,
        name: "Test \(id)",
        description: "test server",
        transport: .stdio(MCPStdioConfiguration(command: "/usr/bin/true")),
        state: .configured,
        trustLevel: .untrusted,
        enabled: enabled,
        toolPolicy: policy
    )
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - mcp.list_servers
// ═══════════════════════════════════════════════════════════════════

@Suite("MCPListServersTool")
struct MCPListServersToolTests {

    @Test("Empty registry returns empty list")
    func emptyRegistry() async throws {
        let registry = MCPServerRegistry()
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let tool = MCPListServersTool(mcp: mcp)
        let out = try await tool.call(MCPListServersInput(), context: makeContext())
        #expect(out.servers.isEmpty)
    }

    @Test("Reports registered servers with trust + enabled state")
    func reportsServers() async throws {
        let registry = MCPServerRegistry()
        try await registry.addServer(stdioProfile(id: "alpha"))
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let tool = MCPListServersTool(mcp: mcp)
        let out = try await tool.call(MCPListServersInput(), context: makeContext())
        #expect(out.servers.count == 1)
        #expect(out.servers[0].id == "alpha")
        #expect(out.servers[0].trustLevel == "untrusted")
        #expect(out.servers[0].enabled == true)
        #expect(out.servers[0].transport == "stdio")
    }

    @Test("Descriptor metadata is read-only / never approved")
    func descriptor() {
        #expect(MCPListServersTool.name.rawValue == "mcp.list_servers")
        #expect(MCPListServersTool.permission == .mcpRead)
        #expect(MCPListServersTool.risk == .readOnly)
        #expect(MCPListServersTool.approval == .never)
        #expect(MCPListServersTool.toolset == .mcp)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - mcp.list_tools
// ═══════════════════════════════════════════════════════════════════

@Suite("MCPListToolsTool")
struct MCPListToolsToolTests {

    @Test("Unknown server throws")
    func unknownServer() async {
        let registry = MCPServerRegistry()
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let tool = MCPListToolsTool(mcp: mcp)
        await #expect(throws: ToolError.self) {
            try await tool.call(MCPListToolsInput(serverID: "missing"), context: makeContext())
        }
    }

    @Test("Untrusted server reports every tool at the policy default risk")
    func untrustedRiskFloor() async throws {
        // MCPServerRegistry.classifyToolRisk takes the cautious path for
        // untrusted servers: every tool is reported at
        // `max(toolPolicy.defaultRisk, .medium)`, never below. The
        // MCPPermissionMapper heuristic (read/write/destructive) only
        // applies to trust levels above `.untrusted`.
        let registry = MCPServerRegistry()
        try await registry.addServer(stdioProfile(id: "alpha"))
        try await registry.registerDiscoveredTools("alpha", tools: [
            MCPToolDescriptor(serverID: "alpha", name: "search_docs",
                              description: "Search the documentation",
                              inputSchemaJSON: "{}"),
            MCPToolDescriptor(serverID: "alpha", name: "delete_doc",
                              description: "Delete a doc — destructive",
                              inputSchemaJSON: "{}"),
        ])
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let tool = MCPListToolsTool(mcp: mcp)
        let out = try await tool.call(MCPListToolsInput(serverID: "alpha"), context: makeContext())
        #expect(out.serverID == "alpha")
        #expect(out.tools.count == 2)
        for entry in out.tools {
            #expect(entry.estimatedRisk == "medium")
        }
        // Carries the discovered metadata back to the agent so it can
        // construct valid arguments without another round-trip.
        let search = out.tools.first { $0.name == "search_docs" }
        #expect(search?.description == "Search the documentation")
        #expect(search?.inputSchemaJSON == "{}")
    }

    @Test("Descriptor metadata")
    func descriptor() {
        #expect(MCPListToolsTool.name.rawValue == "mcp.list_tools")
        #expect(MCPListToolsTool.permission == .mcpRead)
        #expect(MCPListToolsTool.risk == .readOnly)
        #expect(MCPListToolsTool.approval == .never)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - mcp.call (policy gates, without a live transport)
// ═══════════════════════════════════════════════════════════════════

@Suite("MCPCallTool policy gates")
struct MCPCallToolGateTests {

    @Test("Static descriptor is high-risk + askEveryTime")
    func descriptor() {
        // This is the safety contract the wiring plan documents:
        // imported MCP tools are untrusted, so every call is gated at
        // the registry's high-risk approval prompt regardless of how the
        // MCP server classifies its own tool.
        #expect(MCPCallTool.name.rawValue == "mcp.call")
        #expect(MCPCallTool.permission == .mcpExecute)
        #expect(MCPCallTool.risk == .high)
        #expect(MCPCallTool.approval == .askEveryTime)
        #expect(MCPCallTool.toolset == .mcp)
    }

    @Test("Unknown server rejects before dialing")
    func unknownServer() async {
        let registry = MCPServerRegistry()
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let audit = MockAudit()
        let tool = MCPCallTool(mcp: mcp, audit: audit)
        await #expect(throws: ToolError.self) {
            try await tool.call(
                MCPCallInput(serverID: "missing", toolName: "anything"),
                context: makeContext()
            )
        }
        // No tool-call-started audit should fire since we never got past
        // the unknown-server guard.
        let entries = await audit.entries
        #expect(entries.isEmpty)
    }

    @Test("Disabled server is refused")
    func disabledServer() async throws {
        let registry = MCPServerRegistry()
        try await registry.addServer(stdioProfile(id: "alpha", enabled: false))
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let audit = MockAudit()
        let tool = MCPCallTool(mcp: mcp, audit: audit)
        await #expect(throws: ToolError.self) {
            try await tool.call(
                MCPCallInput(serverID: "alpha", toolName: "anything"),
                context: makeContext()
            )
        }
        let entries = await audit.entries
        #expect(entries.isEmpty)
    }

    @Test("Denylisted tool is refused even on enabled server")
    func denylistedTool() async throws {
        let registry = MCPServerRegistry()
        try await registry.addServer(stdioProfile(id: "alpha", denylist: ["evil_tool"]))
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let audit = MockAudit()
        let tool = MCPCallTool(mcp: mcp, audit: audit)
        await #expect(throws: ToolError.self) {
            try await tool.call(
                MCPCallInput(serverID: "alpha", toolName: "evil_tool"),
                context: makeContext()
            )
        }
        let entries = await audit.entries
        #expect(entries.isEmpty)
    }

    @Test("Allowlist-only mode rejects tools not on the list")
    func allowlistMode() async throws {
        let registry = MCPServerRegistry()
        try await registry.addServer(stdioProfile(id: "alpha", allowlist: ["safe_read"]))
        let connector = MCPConnector()
        let mcp = MCPDependencies(registry: registry, connector: connector)
        let audit = MockAudit()
        let tool = MCPCallTool(mcp: mcp, audit: audit)
        await #expect(throws: ToolError.self) {
            try await tool.call(
                MCPCallInput(serverID: "alpha", toolName: "anything_else"),
                context: makeContext()
            )
        }
        let entries = await audit.entries
        #expect(entries.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Argument conversion
// ═══════════════════════════════════════════════════════════════════

@Suite("MCPCallTool argument conversion")
struct MCPCallArgConversionTests {

    @Test("Empty object converts to empty arguments map")
    func empty() {
        let out = MCPCallTool.convertArgs(.object([:]))
        #expect(out.isEmpty)
    }

    @Test("Top-level non-object becomes empty map")
    func nonObject() {
        let out = MCPCallTool.convertArgs(.string("nope"))
        #expect(out.isEmpty)
    }

    @Test("Primitive types round-trip into JSONRPCValue equivalents")
    func primitives() {
        let value: JSONValue = .object([
            "s": .string("hello"),
            "i": .int(42),
            "d": .double(1.5),
            "b": .bool(true),
            "n": .null,
        ])
        let out = MCPCallTool.convertArgs(value)
        #expect(out["s"] == .string("hello"))
        #expect(out["i"] == .int(42))
        #expect(out["d"] == .double(1.5))
        #expect(out["b"] == .bool(true))
        #expect(out["n"] == .null)
    }

    @Test("Nested arrays and objects preserve structure")
    func nested() {
        let value: JSONValue = .object([
            "items": .array([
                .object(["k": .string("v")]),
                .int(7),
            ])
        ])
        let out = MCPCallTool.convertArgs(value)
        guard case .array(let arr) = out["items"] else {
            Issue.record("Expected items to be an array")
            return
        }
        #expect(arr.count == 2)
        guard case .object(let obj) = arr[0] else {
            Issue.record("Expected first element to be object")
            return
        }
        #expect(obj["k"] == .string("v"))
        #expect(arr[1] == .int(7))
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - DefaultToolRegistrar integration
// ═══════════════════════════════════════════════════════════════════

@Suite("DefaultToolRegistrar MCP wiring")
struct DefaultToolRegistrarMCPTests {

    @Test("registerAll with nil mcp does not register MCP tools")
    func mcpNilSkipsRegistration() async {
        let firewall = SwooshFirewallActor()
        let audit = MockAudit()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        let deps = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: NullFileAccess(),
            processRunner: NullProcessRunner()
        )
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: deps)
        #expect(await registry.getToolSchema(name: "mcp.list_servers") == nil)
        #expect(await registry.getToolSchema(name: "mcp.list_tools") == nil)
        #expect(await registry.getToolSchema(name: "mcp.call") == nil)
    }

    @Test("registerAll with mcp wires all three MCP tools")
    func mcpWiring() async {
        let firewall = SwooshFirewallActor()
        let audit = MockAudit()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        let deps = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: NullFileAccess(),
            processRunner: NullProcessRunner()
        )
        let mcp = MCPDependencies(
            registry: MCPServerRegistry(),
            connector: MCPConnector()
        )
        await DefaultToolRegistrar.registerAll(
            into: registry,
            dependencies: deps,
            mcp: mcp
        )
        #expect(await registry.getToolSchema(name: "mcp.list_servers") != nil)
        #expect(await registry.getToolSchema(name: "mcp.list_tools") != nil)
        #expect(await registry.getToolSchema(name: "mcp.call") != nil)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Stubs (test-only, copied from SwooshToolsTests pattern)
// ═══════════════════════════════════════════════════════════════════

private struct NullFileAccess: FileAccessing {
    func resolveBookmark(id: String) async throws -> URL { URL(fileURLWithPath: "/tmp/test") }
    func listDirectory(root: URL, relativePath: String?, includeHidden: Bool, maxDepth: Int) async throws -> [FileEntry] { [] }
    func readFile(root: URL, relativePath: String, maxBytes: Int?) async throws -> (content: String, truncated: Bool, redaction: RedactionReport?) { ("", false, nil) }
    func writeFile(root: URL, relativePath: String, content: String, createBackup: Bool) async throws -> (bytesWritten: Int64, backupPath: String?) { (0, nil) }
    func deleteFile(root: URL, relativePath: String) async throws {}
    func searchFiles(root: URL, query: String, filePattern: String?, maxResults: Int?) async throws -> [FileSearchMatch] { [] }
}

private struct NullProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String], workingDirectory: URL?, environment: [String: String]?) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
