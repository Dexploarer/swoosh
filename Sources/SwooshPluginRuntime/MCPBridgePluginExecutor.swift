// SwooshPluginRuntime/MCPBridgePluginExecutor.swift — 0.8C MCP-bridge kind
//
// An `mcpBridge` plugin is a thin façade over an MCP server already
// configured in the daemon's `MCPServerRegistry`. The manifest names the
// MCP server ID; the plugin's tool list mirrors the MCP server's
// `tools/list` output, and each tool call is routed verbatim to the
// server's `tools/call`. The point is to let plugin metadata
// (description, permissions, approval policy, audit lineage) wrap an
// existing MCP server so it can be enabled and audited like any other
// plugin — without the daemon needing to know about MCP at the firewall
// or audit layer.
//
// Lifecycle: one short-lived MCP client per call. MCP servers are stateful
// but stdio transports start cheaply and the handshake is one round trip;
// connecting per call keeps the bridge thread-safe without coordinating
// long-lived sessions. A later optimisation can cache per-server clients.

import Foundation
import SwooshMCP
import SwooshPlugins
import SwooshTools

public struct MCPBridgePluginExecutor: PluginExecutor {
    public let kind: PluginKind = .mcpBridge
    public let registry: MCPServerRegistry
    public let connector: MCPConnector

    public init(registry: MCPServerRegistry, connector: MCPConnector) {
        self.registry = registry
        self.connector = connector
    }

    public func call(
        manifest: PluginManifest,
        toolName: String,
        args: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        guard case .mcpServer(let serverID) = manifest.entrypoint else {
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "manifest kind is `mcpBridge` but entrypoint is \(manifest.entrypoint)"
            )
        }
        guard let profile = await registry.getServer(serverID) else {
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "MCP server `\(serverID)` is not registered. Add it via `swoosh mcp ...` first."
            )
        }
        guard profile.enabled else {
            throw PluginError.notEnabled("MCP server `\(serverID)` is registered but disabled")
        }

        #if os(macOS) || os(Linux)
        let client = try await connector.makeClient(for: profile)
        do {
            try await client.connect()
            _ = try await client.initialize()
            let mcpArgs = try Self.transcodeArgs(args, pluginID: manifest.id)
            let result = try await client.callTool(name: toolName, arguments: mcpArgs)
            await client.disconnect()
            if result.isError {
                throw PluginError.toolFailed("MCP \(serverID)/\(toolName): \(result.text)")
            }
            // Try to interpret the MCP result text as JSON. If it parses,
            // we return the structured value so callers can extract
            // fields. Otherwise we wrap the raw text in `{"text": "..."}`.
            return Self.parseResultText(result.text)
        } catch let error as PluginError {
            await client.disconnect()
            throw error
        } catch {
            await client.disconnect()
            throw PluginError.toolFailed("MCP \(serverID)/\(toolName): \(error.localizedDescription)")
        }
        #else
        throw PluginError.missingEntrypoint(
            pluginID: manifest.id,
            detail: "MCP-bridge plugins are only available on macOS/Linux hosts"
        )
        #endif
    }

    // MARK: - Helpers

    /// Convert a `JSONValue` (Swoosh's wire format) to an MCP arguments
    /// dict (`[String: JSONRPCValue]`). MCP's `tools/call` always expects
    /// an object at the top level; scalar args throw.
    static func transcodeArgs(_ value: JSONValue, pluginID: String) throws -> [String: JSONRPCValue] {
        // .null at the top level → empty arguments.
        if case .null = value { return [:] }
        guard case .object = value else {
            throw PluginError.toolFailed(
                "MCP bridge plugin \(pluginID): tool arguments must be a JSON object, got \(value)"
            )
        }
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONRPCValue.self, from: data)
        guard case .object(let dict) = decoded else {
            throw PluginError.toolFailed(
                "MCP bridge plugin \(pluginID): transcoded args were not an object"
            )
        }
        return dict
    }

    /// MCP tool calls return free-form text. If the text parses as JSON,
    /// surface it as a structured `JSONValue` so consumers can extract
    /// fields. Otherwise wrap the raw text in `{"text": "..."}` so the
    /// envelope is still an object.
    static func parseResultText(_ text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object(["text": .string(text)])
        }
        return parsed
    }
}
