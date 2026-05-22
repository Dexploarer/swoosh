// Tests/SwooshPluginRuntimeTests/MCPBridgePluginExecutorTests.swift — 0.8C
//
// Covers the error-path and arg-transcoding behaviour of
// MCPBridgePluginExecutor. The happy-path test goes through SwooshMCP's
// own mock infrastructure (separate test target) — the bridge itself is
// thin enough that the unit-test value here is in the contract checks,
// not in re-mocking the JSON-RPC protocol.

import Testing
import Foundation
@testable import SwooshMCP
@testable import SwooshPlugins
@testable import SwooshPluginRuntime
@testable import SwooshTools

// MARK: - Helpers

private func makeRegistry(serverID: String, enabled: Bool = true) async -> MCPServerRegistry {
    let registry = MCPServerRegistry()
    let profile = MCPServerProfile(
        id: serverID, name: "Mock \(serverID)",
        transport: .stdio(.init(command: "/bin/false")),
        state: enabled ? .connected : .configured,
        enabled: enabled
    )
    try? await registry.addServer(profile)
    return registry
}

private func makeMCPManifest(id: String = "mcp-demo", serverID: String, toolName: String = "echo") -> PluginManifest {
    PluginManifest(
        id: id, name: id, version: "1.0.0",
        kind: .mcpBridge,
        entrypoint: .mcpServer(serverID: serverID),
        requestedPermissions: ["mcpExecute"],
        tools: [PluginToolManifest(
            name: toolName, description: "MCP-bridged echo",
            permission: .mcpExecute, risk: .medium, requiresApproval: false
        )]
    )
}


// MARK: - Tests

@Suite("MCPBridgePluginExecutor")
struct MCPBridgePluginExecutorTests {

    @Test("transcodeArgs accepts an object")
    func transcodeAcceptsObject() throws {
        let dict = try MCPBridgePluginExecutor.transcodeArgs(
            .object(["msg": .string("hi"), "n": .int(2)]),
            pluginID: "test"
        )
        if case .string(let s) = dict["msg"] { #expect(s == "hi") } else { Issue.record("msg missing") }
    }

    @Test("transcodeArgs treats null as empty")
    func transcodeAcceptsNull() throws {
        let dict = try MCPBridgePluginExecutor.transcodeArgs(.null, pluginID: "test")
        #expect(dict.isEmpty)
    }

    @Test("transcodeArgs rejects scalars")
    func transcodeRejectsScalars() {
        do {
            _ = try MCPBridgePluginExecutor.transcodeArgs(.string("oops"), pluginID: "test")
            Issue.record("expected throw")
        } catch PluginError.toolFailed {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("parseResultText returns JSON when parseable")
    func parseResultTextParses() {
        let value = MCPBridgePluginExecutor.parseResultText("{\"a\":1}")
        if case .object(let dict) = value, case .int(let n) = dict["a"] {
            #expect(n == 1)
        } else {
            Issue.record("expected parsed object, got: \(value)")
        }
    }

    @Test("parseResultText wraps non-JSON text")
    func parseResultTextWraps() {
        let value = MCPBridgePluginExecutor.parseResultText("hello world")
        guard case .object(let dict) = value, case .string(let s) = dict["text"] else {
            Issue.record("expected wrapped text, got \(value)")
            return
        }
        #expect(s == "hello world")
    }

    @Test("missing server → missingEntrypoint")
    func missingServer() async throws {
        let registry = await makeRegistry(serverID: "exists")
        let connector = MCPConnector(secretResolver: { _ in nil })
        let executor = MCPBridgePluginExecutor(registry: registry, connector: connector)
        let manifest = makeMCPManifest(serverID: "does-not-exist")
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected missingEntrypoint")
        } catch PluginError.missingEntrypoint(_, let detail) {
            #expect(detail.contains("does-not-exist"))
        }
    }

    @Test("disabled server → notEnabled")
    func disabledServer() async throws {
        let registry = await makeRegistry(serverID: "off", enabled: false)
        let connector = MCPConnector(secretResolver: { _ in nil })
        let executor = MCPBridgePluginExecutor(registry: registry, connector: connector)
        let manifest = makeMCPManifest(serverID: "off")
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected notEnabled")
        } catch PluginError.notEnabled {
            // expected
        }
    }

    @Test("wrong entrypoint kind → missingEntrypoint")
    func wrongEntrypoint() async throws {
        let registry = await makeRegistry(serverID: "any")
        let connector = MCPConnector(secretResolver: { _ in nil })
        let executor = MCPBridgePluginExecutor(registry: registry, connector: connector)
        let manifest = PluginManifest(
            id: "wrong", name: "wrong", version: "1.0",
            kind: .mcpBridge,
            entrypoint: .swiftModule("not-an-mcp"),  // mismatched
            requestedPermissions: ["mcpExecute"],
            tools: [PluginToolManifest(
                name: "echo", description: "",
                permission: .mcpExecute, risk: .medium, requiresApproval: false
            )]
        )
        do {
            _ = try await executor.call(
                manifest: manifest, toolName: "echo",
                args: .null, context: ToolContext(sessionID: "t")
            )
            Issue.record("expected missingEntrypoint")
        } catch PluginError.missingEntrypoint {
            // expected
        }
    }
}
