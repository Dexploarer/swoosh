// SwooshPluginRuntime/SwiftPluginExecutor.swift — 0.8B Swift Plugin Executor
//
// Resolves a `SwiftPluginEntrypoint` from the compile-time
// `SwiftPluginRegistry` and forwards the call. No isolation beyond what the
// host already provides — Swift plugins are trusted code linked into the
// daemon, so the sandbox concept doesn't apply the same way it does to
// executable / wasm plugins.

import Foundation
import SwooshPlugins
import SwooshTools

public struct SwiftPluginExecutor: PluginExecutor {
    public let kind: PluginKind = .swift
    private let registry: SwiftPluginRegistry

    public init(registry: SwiftPluginRegistry) {
        self.registry = registry
    }

    public func call(
        manifest: PluginManifest,
        toolName: String,
        args: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue {
        guard let entrypoint = await registry.get(manifest.id) else {
            throw PluginError.missingEntrypoint(
                pluginID: manifest.id,
                detail: "no Swift entrypoint registered for \(manifest.id) — did the daemon forget to call SwiftPluginRegistry.register at startup?"
            )
        }
        return try await entrypoint.call(toolName: toolName, args: args, context: context)
    }

    /// Hook called by PluginHost on enable. Looks up the entrypoint and
    /// forwards the lifecycle call. Silent no-op when the entrypoint
    /// isn't registered — the host has already raised `missingEntrypoint`
    /// for that case before this method runs.
    public func lifecycleInitialize(manifest: PluginManifest) async throws {
        guard let entrypoint = await registry.get(manifest.id) else { return }
        try await entrypoint.initialize(manifest: manifest)
    }

    /// Hook called by PluginHost on disable. Errors here are logged but
    /// not propagated — see PluginHost.disable for rationale.
    public func lifecycleDispose(manifest: PluginManifest) async throws {
        guard let entrypoint = await registry.get(manifest.id) else { return }
        try await entrypoint.dispose()
    }
}
