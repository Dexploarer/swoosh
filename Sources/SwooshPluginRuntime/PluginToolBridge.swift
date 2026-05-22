// SwooshPluginRuntime/PluginToolBridge.swift — 0.8B Plugin → ToolRegistry shim
//
// The bridge is what `ToolRegistry` actually stores for a plugin's tool. It
// implements `AnySwooshTool` directly — `TypeErasedTool<T>` wouldn't fit
// because plugin tools are dynamic (one Swift type can't carry per-instance
// permission/risk metadata). The descriptor is derived from
// `PluginToolManifest` at bridge construction time and never mutates.
//
// Audit trail: tool-call start / completed / failed events go through
// `PluginRegistry.recordEvent` so they reach the same external `AuditLogging`
// the registry was wired with. The outer `ToolRegistry.execute` still writes
// its own ordinary `toolCallStarted` / `toolCallSucceeded` entries; the
// plugin events are additional context, not a replacement.
//
// Defense-in-depth: the bridge re-checks the plugin's `enabled` flag at
// call time. Even if a future bug left a stale bridge in the registry after
// disable, the call would be rejected here.

import Foundation
import SwooshPlugins
import SwooshTools

public struct PluginToolBridge: AnySwooshTool {
    public let descriptor: ToolDescriptor
    private let pluginID: String
    private let toolName: String
    private let executor: any PluginExecutor
    private let registry: PluginRegistry

    public init(
        pluginID: String,
        manifest: PluginManifest,
        tool: PluginToolManifest,
        executor: any PluginExecutor,
        registry: PluginRegistry
    ) {
        self.pluginID = pluginID
        self.toolName = tool.name
        self.executor = executor
        self.registry = registry
        self.descriptor = ToolDescriptor(
            id: tool.swooshToolName,
            name: tool.swooshToolName,
            displayName: tool.name,
            description: tool.description,
            inputSchema: JSONSchema(type: "object", description: "Input for plugin tool \(tool.name)"),
            outputSchema: JSONSchema(type: "object", description: "Output from plugin tool \(tool.name)"),
            permission: tool.permission,
            risk: tool.risk,
            approval: tool.requiresApproval ? .askEveryTime : .never,
            toolset: .plugins,
            platforms: [.macOS, .linux]
        )
    }

    public func callJSON(_ input: JSONValue, context: ToolContext) async throws -> JSONValue {
        guard let manifest = await registry.getPlugin(pluginID), manifest.enabled else {
            throw PluginError.notEnabled(pluginID)
        }
        await registry.recordEvent(.init(
            kind: .toolCallStarted, pluginID: pluginID,
            message: "Plugin tool started: \(toolName)"
        ))
        do {
            let output = try await executor.call(
                manifest: manifest, toolName: toolName,
                args: input, context: context
            )
            await registry.recordEvent(.init(
                kind: .toolCallCompleted, pluginID: pluginID,
                message: "Plugin tool completed: \(toolName)"
            ))
            return output
        } catch {
            await registry.recordEvent(.init(
                kind: .toolCallFailed, pluginID: pluginID,
                message: "Plugin tool failed: \(toolName): \(error.localizedDescription)"
            ))
            throw error
        }
    }
}
