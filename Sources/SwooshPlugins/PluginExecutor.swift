// SwooshPlugins/PluginExecutor.swift — 0.8B Plugin Executor Contract
//
// One executor per `PluginKind`. The runtime (`SwooshPluginRuntime`) owns
// concrete executors that load Swift modules, spawn executables, and host
// wasm. This file holds only the contract so the cross-platform types
// module never pulls in `Foundation.Process` or a wasm runtime — the iOS
// app links against `SwooshPlugins` but never against the executor module.

import Foundation
import SwooshTools

/// Per-kind execution boundary. The bridge tool (registered with
/// `ToolRegistry`) calls into this contract after the firewall and the
/// approval layer have already cleared the call. Executors are *not*
/// responsible for permission checks or audit — those happen above them.
public protocol PluginExecutor: Sendable {
    /// `kind` this executor handles. The host dispatches on this value.
    var kind: PluginKind { get }

    /// Invoke `toolName` on the named plugin with `args`.
    /// - Throws `PluginError.notEnabled` if the plugin isn't loaded.
    /// - Throws `PluginError.toolNotRegistered` if `toolName` isn't part of
    ///   the plugin's manifest.
    func call(
        manifest: PluginManifest,
        toolName: String,
        args: JSONValue,
        context: ToolContext
    ) async throws -> JSONValue
}
