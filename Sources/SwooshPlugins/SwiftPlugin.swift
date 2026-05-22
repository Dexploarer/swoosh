// SwooshPlugins/SwiftPlugin.swift — 0.8B Swift-kind Plugin Contract
//
// A `swift` plugin is a Swift type linked into the daemon binary at compile
// time. It self-registers with `SwiftPluginRegistry` during startup. There
// is intentionally no dynamic loading: dynamic Swift libraries can't be
// signed and trusted on macOS without significant ceremony, and on iOS
// they aren't allowed at all. Compile-time linkage gives us a real
// supply-chain story for free — the plugin's source ships in the repo.
//
// An executable or wasm plugin's bytes ship in `Plugins/<id>/`; a swift
// plugin's bytes are baked into `swooshd`. The manifest still lives in
// `Plugins/<id>/manifest.json` so the discovery surface is uniform.

import Foundation
import SwooshTools

/// Contract for a Swift plugin entrypoint. Implementors are usually
/// `struct`s (Sendable, value-typed) registered once at daemon startup.
///
/// Lifecycle hooks (`initialize` / `dispose`) mirror the elizaOS plugin
/// shape — they default to no-ops so existing entrypoints stay forward
/// compatible. The host calls them around enable/disable, giving Swift
/// plugins a place to set up timers or shared state without ad-hoc
/// global init.
public protocol SwiftPluginEntrypoint: Sendable {
    /// The plugin's manifest ID. Must match `manifest.id` and the
    /// `swiftModule(_)` argument in the manifest's `entrypoint`.
    static var pluginID: String { get }

    /// Dispatch a tool call. `toolName` is the bare manifest name
    /// (e.g. `"echo"`), not the `plugin.echo` form the registry uses —
    /// the bridge strips the prefix before dispatch.
    func call(
        toolName: String,
        args: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue

    /// Called once on enable, after permissions are granted and tools
    /// are about to be bridged into the registry. Use this for setup
    /// that benefits from running once per enable rather than per call
    /// (warm caches, validate config, etc.). Throwing from `initialize`
    /// aborts the enable.
    func initialize(manifest: PluginManifest) async throws

    /// Called on disable, after the plugin's tools have been removed
    /// from the registry. Use this to release resources. Throws are
    /// logged but don't fail the disable operation.
    func dispose() async throws
}

public extension SwiftPluginEntrypoint {
    func initialize(manifest: PluginManifest) async throws {}
    func dispose() async throws {}
}

/// Compile-time registry of Swift plugin entrypoints. Populated at daemon
/// startup with `register(_:)` calls. `SwiftPluginExecutor` looks up entries
/// here at call time.
public actor SwiftPluginRegistry {
    private var entries: [String: any SwiftPluginEntrypoint] = [:]

    public init() {}

    /// Register an entrypoint under its declared `pluginID`. The common
    /// case — one Swift type per plugin, both `static let pluginID` and
    /// the manifest agreeing on the same string.
    public func register(_ entrypoint: any SwiftPluginEntrypoint) {
        entries[Swift.type(of: entrypoint).pluginID] = entrypoint
    }

    /// Register an entrypoint under an explicit ID. Useful when one Swift
    /// type backs multiple manifests (rare in production, common in tests
    /// where a generic entrypoint stands in for several distinct plugins).
    public func register(id: String, _ entrypoint: any SwiftPluginEntrypoint) {
        entries[id] = entrypoint
    }

    public func get(_ pluginID: String) -> (any SwiftPluginEntrypoint)? {
        entries[pluginID]
    }

    public func list() -> [String] {
        entries.keys.sorted()
    }
}
