// Tests/SwooshPluginsTests/PluginTests.swift — 0.8A Plugin Tests

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// Fixtures
// ═══════════════════════════════════════════════════════════════

func makePlugin(id: String = "test-plugin", tools: [PluginToolManifest] = [
    PluginToolManifest(name: "plugin.status", description: "Status", risk: .readOnly, requiresApproval: false),
    PluginToolManifest(name: "plugin.action", description: "Do action", risk: .medium, requiresApproval: true),
]) -> PluginManifest {
    PluginManifest(
        id: id, name: "Test Plugin", version: "1.0.0",
        description: "A test plugin", author: "Swoosh Team",
        requestedPermissions: ["toolRead", "networkAccess"],
        tools: tools
    )
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Plugin Manifest Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Plugin Manifest")
struct PluginManifestTests {

    @Test("Manifest decodes")
    func manifestDecodes() {
        let p = makePlugin()
        #expect(p.name == "Test Plugin")
        #expect(p.version == "1.0.0")
        #expect(p.tools.count == 2)
    }

    @Test("Plugin defaults to disabled")
    func defaultDisabled() {
        #expect(!makePlugin().enabled)
    }

    @Test("Tool swoosh name prefixed")
    func toolNamePrefixed() {
        let t = PluginToolManifest(name: "spotify.play", description: "Play", risk: .medium)
        #expect(t.swooshToolName == "plugin.spotify.play")
    }

    @Test("Requested permissions visible")
    func permissionsVisible() {
        let p = makePlugin()
        #expect(p.requestedPermissions.contains("networkAccess"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Plugin Registry Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Plugin Registry")
struct PluginRegistryTests {

    @Test("Register plugin")
    func registerPlugin() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let list = await reg.list()
        #expect(list.count == 1)
    }

    @Test("Duplicate register throws")
    func duplicateThrows() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        do {
            try await reg.register(makePlugin())
            Issue.record("Should throw")
        } catch is PluginError {}
    }

    @Test("Inspect plugin")
    func inspectPlugin() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let p = try await reg.inspect("test-plugin")
        #expect(p.name == "Test Plugin")
    }

    @Test("Enable plugin registers tools")
    func enableRegistersTools() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        try await reg.enable("test-plugin")
        let p = await reg.getPlugin("test-plugin")
        #expect(p?.enabled == true)
        #expect(await reg.isToolRegistered("plugin.plugin.status"))
    }

    @Test("Disable unregisters tools")
    func disableUnregistersTools() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        try await reg.enable("test-plugin")
        try await reg.disable("test-plugin")
        let isRegistered = await reg.isToolRegistered("plugin.plugin.status")
        #expect(!isRegistered)
    }

    @Test("Plugin for tool lookup")
    func pluginForTool() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        try await reg.enable("test-plugin")
        let pluginID = await reg.pluginForTool("plugin.plugin.status")
        #expect(pluginID == "test-plugin")
    }

    @Test("List tools for plugin")
    func listTools() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let tools = try await reg.listTools(pluginID: "test-plugin")
        #expect(tools.count == 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Sandbox Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Plugin Sandbox")
struct PluginSandboxTests {

    @Test("Safe default denies filesystem read")
    func defaultDeniesRead() {
        #expect(!PluginSandboxPolicy.safeDefault.allowFilesystemRead)
    }

    @Test("Safe default denies filesystem write")
    func defaultDeniesWrite() {
        #expect(!PluginSandboxPolicy.safeDefault.allowFilesystemWrite)
    }

    @Test("Safe default denies network")
    func defaultDeniesNetwork() {
        #expect(!PluginSandboxPolicy.safeDefault.allowNetwork)
    }

    @Test("Safe default denies process spawn")
    func defaultDeniesProcess() {
        #expect(!PluginSandboxPolicy.safeDefault.allowProcessSpawn)
    }

    @Test("Sandbox validates filesystem read")
    func sandboxValidatesRead() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let allowed = try await reg.validateSandbox(pluginID: "test-plugin", action: .filesystemRead)
        #expect(!allowed) // default sandbox denies
    }

    @Test("Sandbox validates network")
    func sandboxValidatesNetwork() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let allowed = try await reg.validateSandbox(pluginID: "test-plugin", action: .network)
        #expect(!allowed) // default sandbox denies
    }

    @Test("Sandbox validates process spawn")
    func sandboxValidatesProcess() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let allowed = try await reg.validateSandbox(pluginID: "test-plugin", action: .processSpawn)
        #expect(!allowed) // default sandbox denies
    }

    @Test("Sandbox violation recorded in audit")
    func sandboxViolationAudited() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        _ = try await reg.validateSandbox(pluginID: "test-plugin", action: .filesystemRead)
        let log = await reg.getAuditLog(pluginID: "test-plugin")
        #expect(log.contains { $0.kind == .sandboxViolation })
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Plugin Audit Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Plugin Audit")
struct PluginAuditTests {

    @Test("Register writes audit")
    func registerAudit() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let log = await reg.getAuditLog()
        #expect(log.contains { $0.kind == .discovered })
    }

    @Test("Enable writes audit")
    func enableAudit() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        try await reg.enable("test-plugin")
        let log = await reg.getAuditLog()
        #expect(log.contains { $0.kind == .enabled })
        #expect(log.contains { $0.kind == .toolRegistered })
    }

    @Test("Disable writes audit")
    func disableAudit() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        try await reg.enable("test-plugin")
        try await reg.disable("test-plugin")
        let log = await reg.getAuditLog()
        #expect(log.contains { $0.kind == .disabled })
    }

    @Test("Audit filtered by pluginID")
    func auditFiltered() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin(id: "a"))
        try await reg.register(makePlugin(id: "b"))
        let logA = await reg.getAuditLog(pluginID: "a")
        let logAll = await reg.getAuditLog()
        #expect(logA.count < logAll.count)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Plugin Redaction Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Plugin Redaction")
struct PluginRedactionTests {

    @Test("Redacts private keys")
    func redactsPrivateKey() {
        let r = PluginContentRedactor()
        #expect(!r.redact("-----BEGIN RSA PRIVATE KEY data").contains("-----BEGIN"))
    }

    @Test("Redacts seeds")
    func redactsSeed() {
        let r = PluginContentRedactor()
        #expect(!r.redact("mnemonic: word1 word2").contains("mnemonic:"))
    }

    @Test("Redacts cookies")
    func redactsCookies() {
        let r = PluginContentRedactor()
        #expect(!r.redact("cookie: session=abc").contains("cookie:"))
    }

    @Test("Registry redacts output")
    func registryRedacts() async throws {
        let reg = PluginRegistry()
        let result = await reg.redactOutput("Found -----BEGIN PRIVATE KEY in log")
        #expect(!result.contains("-----BEGIN"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Plugin /why Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Plugin Why")
struct PluginWhyTests {

    @Test("/why explains plugin")
    func whyExplains() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let why = await reg.whyExplanation(pluginID: "test-plugin")
        #expect(why.contains("ToolRegistry"))
        #expect(why.contains("Firewall"))
        #expect(why.contains("redacted"))
    }

    @Test("/why shows sandbox")
    func whyShowsSandbox() async throws {
        let reg = PluginRegistry()
        try await reg.register(makePlugin())
        let why = await reg.whyExplanation(pluginID: "test-plugin")
        #expect(why.contains("Filesystem read: false"))
        #expect(why.contains("Network: false"))
    }
}
