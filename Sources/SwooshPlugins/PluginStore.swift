// SwooshPlugins/PluginStore.swift — 0.8B Plugin Persistence Contract
//
// Plugin manifests live as JSON files on disk; the concrete implementation
// (`FilePluginStore`) lives in `SwooshPluginRuntime` so this module stays
// free of `FileManager` writes and Bonjour-style discovery. This protocol
// is the seam the daemon assembles against at startup and that the test
// suite mocks for unit tests.

import Foundation

/// Persistence layer for plugin manifests. Implementations are expected to
/// write atomically so a crashed enable/disable leaves the previous state
/// intact rather than producing a corrupt manifest. Audit events ride a
/// separate `AuditLogging` channel and are *not* the store's responsibility.
public protocol PluginStore: Sendable {
    /// All known manifests, regardless of enabled state.
    func listAll() async throws -> [PluginManifest]

    /// Fetch one manifest by ID. Returns `nil` for unknown IDs (callers
    /// distinguish "missing" from "corrupt" — corrupt manifests should
    /// throw, not return nil).
    func get(_ id: String) async throws -> PluginManifest?

    /// Insert or replace a manifest. Bumps `updatedAt` on replace.
    func upsert(_ manifest: PluginManifest) async throws

    /// Remove a manifest and any on-disk artifacts under its plugin dir.
    /// No-op for unknown IDs.
    func remove(_ id: String) async throws
}
