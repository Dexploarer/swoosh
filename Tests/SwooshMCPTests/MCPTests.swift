// Tests/SwooshMCPTests/MCPTests.swift — 0.8A MCP Tests

import Testing
import Foundation
@testable import SwooshMCP
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// Fixtures
// ═══════════════════════════════════════════════════════════════

func makeStdioProfile(id: String = "filesystem", enabled: Bool = false) -> MCPServerProfile {
    MCPServerProfile(
        id: id, name: "Filesystem",
        transport: .stdio(MCPStdioConfiguration(command: "npx", arguments: ["@modelcontextprotocol/server-filesystem", "~/Projects"]))
    )
}

func makeHTTPProfile(id: String = "github", localOnly: Bool = true) -> MCPServerProfile {
    MCPServerProfile(
        id: id, name: "GitHub",
        transport: .http(MCPHTTPConfiguration(baseURL: "http://localhost:3000", localOnly: localOnly))
    )
}

func makeTools(serverID: String) -> [MCPToolDescriptor] {
    [
        MCPToolDescriptor(serverID: serverID, name: "read_file", title: "Read File", description: "Read a file"),
        MCPToolDescriptor(serverID: serverID, name: "write_file", title: "Write File", description: "Write a file"),
        MCPToolDescriptor(serverID: serverID, name: "list_directory", title: "List Dir", description: "List directory"),
    ]
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Server Registry Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Server Registry")
struct MCPServerRegistryTests {

    @Test("Add server profile")
    func addServer() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        let servers = await reg.listServers()
        #expect(servers.count == 1)
    }

    @Test("Server defaults to untrusted")
    func defaultsUntrusted() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        let s = await reg.getServer("filesystem")
        #expect(s?.trustLevel == .untrusted)
    }

    @Test("Server defaults to disabled")
    func defaultsDisabled() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        let s = await reg.getServer("filesystem")
        #expect(s?.enabled == false)
    }

    @Test("Enable server")
    func enableServer() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        let s = await reg.getServer("filesystem")
        #expect(s?.enabled == true)
    }

    @Test("Disable server")
    func disableServer() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile(enabled: true))
        try await reg.enableServer("filesystem")
        try await reg.disableServer("filesystem")
        let s = await reg.getServer("filesystem")
        #expect(s?.enabled == false)
    }

    @Test("Remove server")
    func removeServer() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.removeServer("filesystem")
        #expect(await reg.listServers().isEmpty)
    }

    @Test("Duplicate add throws")
    func duplicateThrows() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        do {
            try await reg.addServer(makeStdioProfile())
            Issue.record("Should throw")
        } catch is MCPError {}
    }

    @Test("Stdio config stores no raw secrets")
    func stdioNoRawSecrets() {
        let config = MCPStdioConfiguration(
            command: "npx", arguments: ["server"],
            environmentSecretRefs: ["API_KEY": "keychain://api-key-ref"]
        )
        // environmentSecretRefs are refs, not raw values
        #expect(config.environmentSecretRefs["API_KEY"]!.hasPrefix("keychain://"))
    }

    @Test("Audit log records events")
    func auditLog() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        let log = await reg.getAuditLog()
        #expect(log.count >= 2)
        #expect(log[0].kind == .serverAdded)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Discovery Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Discovery")
struct MCPDiscoveryTests {

    @Test("Register discovered tools")
    func registerTools() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        try await reg.registerDiscoveredTools("filesystem", tools: makeTools(serverID: "filesystem"))
        let tools = await reg.listTools(serverID: "filesystem")
        #expect(tools.count == 3)
    }

    @Test("Discovery fails if server disabled")
    func discoveryFailsDisabled() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        do {
            try await reg.registerDiscoveredTools("filesystem", tools: makeTools(serverID: "filesystem"))
            Issue.record("Should throw")
        } catch is MCPError {}
    }

    @Test("Tool swoosh name is prefixed")
    func toolNamePrefixed() {
        let t = MCPToolDescriptor(serverID: "filesystem", name: "read_file")
        #expect(t.swooshToolName == "mcp.filesystem.read_file")
    }

    @Test("Imported tool names respect allowlist")
    func importedToolNames() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        try await reg.registerDiscoveredTools("filesystem", tools: makeTools(serverID: "filesystem"))
        let names = await reg.importedToolNames(serverID: "filesystem")
        #expect(names.count == 3)
        #expect(names.contains("mcp.filesystem.read_file"))
    }

    @Test("Denied tool not in imported list")
    func deniedToolExcluded() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        try await reg.registerDiscoveredTools("filesystem", tools: makeTools(serverID: "filesystem"))
        try await reg.denyTool(serverID: "filesystem", toolName: "write_file")
        let names = await reg.importedToolNames(serverID: "filesystem")
        #expect(!names.contains("mcp.filesystem.write_file"))
    }

    @Test("Resources registered")
    func resourcesRegistered() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        let res = [MCPResourceDescriptor(serverID: "filesystem", uri: "file:///tmp/test.txt", name: "test")]
        try await reg.registerDiscoveredResources("filesystem", resources: res)
        let listed = await reg.listResources(serverID: "filesystem")
        #expect(listed.count == 1)
    }

    @Test("Prompts registered")
    func promptsRegistered() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        try await reg.registerDiscoveredPrompts("filesystem", prompts: [
            MCPPromptDescriptor(serverID: "filesystem", name: "summarize_file")
        ])
        let listed = await reg.listPrompts(serverID: "filesystem")
        #expect(listed.count == 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Permission & Risk Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Permission Mapping")
struct MCPPermissionMappingTests {

    @Test("Read tool classified readOnly")
    func readToolReadOnly() {
        let mapper = MCPPermissionMapper()
        #expect(mapper.classifyRisk("read_file") == .readOnly)
        #expect(mapper.classifyRisk("list_directory") == .readOnly)
        #expect(mapper.classifyRisk("get_status") == .readOnly)
    }

    @Test("Write tool classified high")
    func writeToolHigh() {
        let mapper = MCPPermissionMapper()
        #expect(mapper.classifyRisk("write_file") == .high)
        #expect(mapper.classifyRisk("create_issue") == .high)
        #expect(mapper.classifyRisk("delete_branch") == .high)
    }

    @Test("Shell/exec tool classified critical")
    func shellToolCritical() {
        let mapper = MCPPermissionMapper()
        #expect(mapper.classifyRisk("run_command") == .critical)
        #expect(mapper.classifyRisk("exec_script") == .critical)
        #expect(mapper.classifyRisk("shell_execute") == .critical)
    }

    @Test("Unknown tool classified medium")
    func unknownToolMedium() {
        let mapper = MCPPermissionMapper()
        #expect(mapper.classifyRisk("do_something_fancy") == .medium)
    }

    @Test("Untrusted server always at least medium risk")
    func untrustedServerMediumRisk() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        let risk = await reg.classifyToolRisk(serverID: "filesystem", toolName: "read_file")
        #expect(risk == .medium) // untrusted server overrides readOnly to medium
    }

    @Test("Default approval requires user approval for all calls")
    func defaultApprovalRequired() {
        let policy = MCPToolPolicy.safeDefault
        #expect(policy.requireUserApprovalForAllCalls)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Resource Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Resource Policy")
struct MCPResourcePolicyTests {

    @Test("Sensitive URI denied")
    func sensitiveURIDenied() {
        let policy = MCPResourcePolicy.safeDefault
        #expect(policy.isURIDenied("file:///home/.env"))
        #expect(policy.isURIDenied("file:///tmp/secret_keys.json"))
        #expect(policy.isURIDenied("data://cookie_jar"))
        #expect(policy.isURIDenied("file:///keys/private_key.pem"))
    }

    @Test("Safe URI allowed")
    func safeURIAllowed() {
        let policy = MCPResourcePolicy.safeDefault
        #expect(!policy.isURIDenied("file:///tmp/readme.md"))
        #expect(!policy.isURIDenied("file:///src/main.swift"))
    }

    @Test("Resource read requires approval by default")
    func resourceReadRequiresApproval() {
        #expect(MCPResourcePolicy.safeDefault.requireApprovalForResourceRead)
    }

    @Test("Resource read gating")
    func resourceReadGating() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        let allowed = try await reg.isResourceReadAllowed(serverID: "filesystem", uri: "file:///tmp/test.txt")
        #expect(allowed)
        let denied = try await reg.isResourceReadAllowed(serverID: "filesystem", uri: "file:///home/.env")
        #expect(!denied)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Swoosh MCP Server Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Swoosh MCP Server")
struct SwooshMCPServerTests {

    @Test("Local-only binds loopback")
    func localOnlyBindsLoopback() {
        let config = SwooshMCPServerConfiguration.safeDefault
        #expect(config.isLocalOnly)
        #expect(config.bindHost == "127.0.0.1")
    }

    @Test("Non-local bind rejected")
    func nonLocalBindRejected() async throws {
        let reg = MCPServerRegistry()
        let config = SwooshMCPServerConfiguration(
            enabled: true, localOnly: false, bindHost: "0.0.0.0", port: 8080,
            exposedToolAllowlist: ["core.status"], exposeResources: false, exposePrompts: false
        )
        do {
            try await reg.validateExposure(config)
            Issue.record("Should throw")
        } catch is MCPError {}
    }

    @Test("Never-expose tools rejected")
    func neverExposeRejected() async throws {
        let reg = MCPServerRegistry()
        let config = SwooshMCPServerConfiguration(
            enabled: true, localOnly: true, bindHost: "127.0.0.1", port: nil,
            exposedToolAllowlist: ["core.status", "approval.resolve"],
            exposeResources: false, exposePrompts: false
        )
        do {
            try await reg.validateExposure(config)
            Issue.record("Should throw for approval.resolve")
        } catch is MCPError {}
    }

    @Test("approval.resolve in never-expose list")
    func approvalResolveNeverExpose() {
        #expect(SwooshMCPServerConfiguration.neverExpose.contains("approval.resolve"))
    }

    @Test("file.write in never-expose list")
    func fileWriteNeverExpose() {
        #expect(SwooshMCPServerConfiguration.neverExpose.contains("file.write"))
    }

    @Test("git.push in never-expose list")
    func gitPushNeverExpose() {
        #expect(SwooshMCPServerConfiguration.neverExpose.contains("git.push"))
    }

    @Test("signing tools in never-expose list")
    func signingNeverExpose() {
        #expect(SwooshMCPServerConfiguration.neverExpose.contains("evm.tx_request_signature"))
        #expect(SwooshMCPServerConfiguration.neverExpose.contains("solana.tx_send_signed"))
    }

    @Test("Safe exposure validates")
    func safeExposureValidates() async throws {
        let reg = MCPServerRegistry()
        try await reg.validateExposure(SwooshMCPServerConfiguration.safeDefault)
        // Should not throw
    }

    @Test("Only allowlisted tools exposable")
    func allowlistedOnly() {
        let config = SwooshMCPServerConfiguration.safeDefault
        #expect(config.isToolExposable("core.status"))
        #expect(!config.isToolExposable("file.patch"))
        #expect(!config.isToolExposable("random.tool"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tool Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Tool Policy")
struct MCPToolPolicyTests {

    @Test("Allow/deny tools")
    func allowDenyTools() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        try await reg.enableServer("filesystem")
        try await reg.registerDiscoveredTools("filesystem", tools: makeTools(serverID: "filesystem"))
        try await reg.denyTool(serverID: "filesystem", toolName: "write_file")
        let s = await reg.getServer("filesystem")!
        #expect(s.toolPolicy.denylist.contains("write_file"))
    }

    @Test("Denylist blocks tool")
    func denylistBlocks() {
        var policy = MCPToolPolicy.safeDefault
        policy.denylist = ["write_file"]
        #expect(!policy.isAllowed("write_file"))
        #expect(policy.isAllowed("read_file"))
    }

    @Test("Allowlist restricts to listed tools")
    func allowlistRestricts() {
        let policy = MCPToolPolicy(
            importTools: true, defaultRisk: .medium,
            allowlist: ["read_file"], denylist: [],
            maxResultBytes: 64_000, requireUserApprovalForAllCalls: true
        )
        #expect(policy.isAllowed("read_file"))
        #expect(!policy.isAllowed("write_file"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Content Redaction Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Redaction")
struct MCPRedactionTests {

    @Test("Redacts private keys")
    func redactsPrivateKey() {
        let r = MCPContentRedactor()
        #expect(!r.redact("-----BEGIN PRIVATE KEY data").contains("-----BEGIN"))
    }

    @Test("Redacts seed phrases")
    func redactsSeed() {
        let r = MCPContentRedactor()
        #expect(!r.redact("seed: word1 word2").contains("seed:"))
    }

    @Test("Redacts cookies")
    func redactsCookies() {
        let r = MCPContentRedactor()
        #expect(!r.redact("cookie: session=abc").contains("cookie:"))
    }

    @Test("Redacts API keys")
    func redactsAPIKey() {
        let r = MCPContentRedactor()
        #expect(!r.redact("api_key: sk_test_123").contains("api_key:"))
    }

    @Test("Truncates long output")
    func truncatesLong() {
        let r = MCPContentRedactor(maxBytes: 100)
        let result = r.redact(String(repeating: "x", count: 500))
        #expect(result.count <= 120) // 100 + truncation marker
    }

    @Test("Safe text passes through")
    func safePassThrough() {
        let r = MCPContentRedactor()
        #expect(r.redact("Hello World") == "Hello World")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Swift Wrapper Generator Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Swift Wrappers")
struct MCPSwiftWrapperTests {

    @Test("Generate wrapper for tools")
    func generateWrapper() {
        let gen = MCPSwiftWrapperGenerator()
        let code = gen.generate(serverID: "filesystem", serverName: "Filesystem", tools: makeTools(serverID: "filesystem"))
        #expect(code.contains("struct FilesystemMCP"))
        #expect(code.contains("func read_file"))
        #expect(code.contains("mcp.filesystem.read_file"))
    }

    @Test("Wrapper calls ToolRegistry not MCP directly")
    func wrapperUsesRegistry() {
        let gen = MCPSwiftWrapperGenerator()
        let code = gen.generate(serverID: "fs", serverName: "FS", tools: makeTools(serverID: "fs"))
        #expect(code.contains("callTool"))
        #expect(code.contains("NOT the MCP server directly"))
    }

    @Test("No raw secrets in generated code")
    func noSecretsInCode() {
        let gen = MCPSwiftWrapperGenerator()
        let code = gen.generate(serverID: "fs", serverName: "FS", tools: makeTools(serverID: "fs"))
        #expect(!code.contains("sk_"))
        #expect(!code.contains("Bearer"))
        #expect(!code.contains("api_key"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - /why Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Why")
struct MCPWhyTests {

    @Test("/why explains MCP server")
    func whyExplains() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        let why = await reg.whyExplanation(serverID: "filesystem", toolName: "read_file")
        #expect(why.contains("ToolRegistry"))
        #expect(why.contains("Firewall"))
        #expect(why.contains("redacted"))
    }

    @Test("/why shows trust level")
    func whyShowsTrust() async throws {
        let reg = MCPServerRegistry()
        try await reg.addServer(makeStdioProfile())
        let why = await reg.whyExplanation(serverID: "filesystem")
        #expect(why.contains("untrusted"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Prompt Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("MCP Prompt Policy")
struct MCPPromptPolicyTests {

    @Test("Prompt preview required by default")
    func previewRequired() {
        #expect(MCPPromptPolicy.safeDefault.requirePreviewBeforeUse)
    }

    @Test("User selection required by default")
    func selectionRequired() {
        #expect(MCPPromptPolicy.safeDefault.requireUserSelection)
    }
}
