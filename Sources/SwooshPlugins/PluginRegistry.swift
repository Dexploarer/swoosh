// SwooshPlugins/PluginRegistry.swift — 0.8B Plugin Registry
//
// The registry tracks every loaded plugin and the set of tool names each
// plugin owns. It does *not* register tools with `ToolRegistry` directly —
// that bridge lives in `SwooshPluginRuntime.PluginHost`, which also handles
// firewall grants and the AnySwooshTool wrapper. Keeping the registry
// transport-free is what lets the iOS app link this module for read-only
// inspection of installed plugins.
//
// Audit forwarding: callers may pass an `AuditLogging` impl on init, in
// which case every `PluginAuditEvent` is also written as an `AuditEntry`
// with kind `.pluginEvent`. The internal in-memory log is still maintained
// for callers that don't wire ActantDB (tests, ad-hoc tools).

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin errors
// ═══════════════════════════════════════════════════════════════════

public enum PluginError: Error, Sendable, CustomStringConvertible {
    case notFound(String)
    case alreadyExists(String)
    case notEnabled(String)
    /// The plugin breached its sandbox contract — timed out, exceeded
    /// `maxOutputBytes`, or returned malformed JSON / unexpected exit
    /// status. Distinct from `toolFailed`, which is the plugin's own
    /// reported error from a successful round-trip.
    case sandboxViolation(String)
    /// A well-behaved plugin returned `{"ok": false, "error": "..."}`.
    /// Routes the message back to the caller as an ordinary tool failure
    /// without conflating it with sandbox breaches.
    case toolFailed(String)
    case toolNotRegistered(String)
    case approvalRequired(String)
    case validationFailed(pluginID: String, errors: [PluginValidationError])
    case missingEntrypoint(pluginID: String, detail: String)

    public var description: String {
        switch self {
        case .notFound(let id): return "plugin not found: \(id)"
        case .alreadyExists(let id): return "plugin already exists: \(id)"
        case .notEnabled(let id): return "plugin not enabled: \(id)"
        case .sandboxViolation(let m): return "sandbox violation: \(m)"
        case .toolFailed(let m): return "plugin tool failed: \(m)"
        case .toolNotRegistered(let n): return "plugin tool not registered: \(n)"
        case .approvalRequired(let id): return "approval required for plugin: \(id)"
        case .validationFailed(let id, let errs):
            let joined = errs.map(\.description).joined(separator: "; ")
            return "plugin \(id) failed validation: \(joined)"
        case .missingEntrypoint(let id, let detail):
            return "plugin \(id) entrypoint unavailable: \(detail)"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin registry
// ═══════════════════════════════════════════════════════════════════

public actor PluginRegistry {
    private var plugins: [String: PluginManifest] = [:]
    private var registeredTools: [String: String] = [:]  // toolName → pluginID
    private var auditLog: [PluginAuditEvent] = []
    private let redactor: PluginContentRedactor
    private let externalAudit: (any AuditLogging)?

    public init(
        redactor: PluginContentRedactor = PluginContentRedactor(),
        audit: (any AuditLogging)? = nil
    ) {
        self.redactor = redactor
        self.externalAudit = audit
    }

    // ── Registration ──────────────────────────────────────────────

    public func register(_ manifest: PluginManifest) async throws {
        guard plugins[manifest.id] == nil else { throw PluginError.alreadyExists(manifest.id) }
        plugins[manifest.id] = manifest
        await appendAudit(.init(
            kind: .discovered, pluginID: manifest.id,
            message: "Plugin registered: \(manifest.name)"
        ))
    }

    public func inspect(_ id: String) async throws -> PluginManifest {
        guard let p = plugins[id] else { throw PluginError.notFound(id) }
        await appendAudit(.init(kind: .inspected, pluginID: id, message: "Plugin inspected"))
        return p
    }

    public func enable(_ id: String) async throws {
        guard var p = plugins[id] else { throw PluginError.notFound(id) }
        p.enabled = true; p.updatedAt = Date()
        plugins[id] = p
        for tool in p.tools {
            registeredTools[tool.swooshToolName] = id
            await appendAudit(.init(
                kind: .toolRegistered, pluginID: id,
                message: "Tool registered: \(tool.swooshToolName)"
            ))
        }
        await appendAudit(.init(kind: .enabled, pluginID: id, message: "Plugin enabled"))
    }

    public func disable(_ id: String) async throws {
        guard var p = plugins[id] else { throw PluginError.notFound(id) }
        p.enabled = false; p.updatedAt = Date()
        plugins[id] = p
        for tool in p.tools { registeredTools.removeValue(forKey: tool.swooshToolName) }
        await appendAudit(.init(kind: .disabled, pluginID: id, message: "Plugin disabled"))
    }

    /// Replace a previously-registered manifest. Used by the runtime when
    /// `FilePluginStore.upsert` writes an updated manifest back to disk —
    /// e.g. after enable/disable mutates the `enabled` flag.
    public func updateManifest(_ manifest: PluginManifest) {
        plugins[manifest.id] = manifest
    }

    // ── Queries ───────────────────────────────────────────────────

    public func list() -> [PluginManifest] { Array(plugins.values).sorted { $0.name < $1.name } }
    public func getPlugin(_ id: String) -> PluginManifest? { plugins[id] }

    public func listTools(pluginID: String) throws -> [PluginToolManifest] {
        guard let p = plugins[pluginID] else { throw PluginError.notFound(pluginID) }
        return p.tools
    }

    public func isToolRegistered(_ toolName: String) -> Bool {
        registeredTools[toolName] != nil
    }

    public func pluginForTool(_ toolName: String) -> String? {
        registeredTools[toolName]
    }

    // ── Sandbox validation ────────────────────────────────────────

    public func validateSandbox(pluginID: String, action: PluginSandboxAction) async throws -> Bool {
        guard let p = plugins[pluginID] else { throw PluginError.notFound(pluginID) }
        switch action {
        case .filesystemRead:
            if !p.sandbox.allowFilesystemRead {
                await appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Filesystem read denied"))
                return false
            }
        case .filesystemWrite:
            if !p.sandbox.allowFilesystemWrite {
                await appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Filesystem write denied"))
                return false
            }
        case .network:
            if !p.sandbox.allowNetwork {
                await appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Network denied"))
                return false
            }
        case .processSpawn:
            if !p.sandbox.allowProcessSpawn {
                await appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Process spawn denied"))
                return false
            }
        }
        return true
    }

    // ── Redaction ─────────────────────────────────────────────────

    public func redactOutput(_ text: String) -> String { redactor.redact(text) }

    // ── Audit ─────────────────────────────────────────────────────

    /// Public hook so the runtime can record plugin-tool-call lifecycle
    /// events (started / completed / failed) without rebuilding its own
    /// log. Also writes to the external `AuditLogging` if one was injected.
    public func recordEvent(_ event: PluginAuditEvent) async {
        await appendAudit(event)
    }

    private func appendAudit(_ event: PluginAuditEvent) async {
        auditLog.append(event)
        if let externalAudit {
            let success: Bool
            switch event.kind {
            case .sandboxViolation, .toolCallFailed: success = false
            default: success = true
            }
            try? await externalAudit.append(AuditEntry(
                kind: .pluginEvent,
                toolName: nil,
                sessionID: nil,
                detail: "[plugin:\(event.pluginID)] \(event.kind.rawValue): \(event.message)",
                success: success
            ))
        }
    }

    public func getAuditLog(pluginID: String? = nil) -> [PluginAuditEvent] {
        if let id = pluginID { return auditLog.filter { $0.pluginID == id } }
        return auditLog
    }

    // ── /why ──────────────────────────────────────────────────────

    public func whyExplanation(pluginID: String) -> String {
        guard let p = plugins[pluginID] else { return "Plugin not found." }
        var lines: [String] = []
        lines.append("Plugin: \(p.name) v\(p.version)")
        lines.append("Kind: \(p.kind.rawValue)")
        lines.append("Enabled: \(p.enabled)")
        lines.append("Requested permissions: \(p.requestedPermissions.joined(separator: ", "))")
        lines.append("")
        lines.append("Sandbox:")
        lines.append("  Filesystem read: \(p.sandbox.allowFilesystemRead)")
        lines.append("  Filesystem write: \(p.sandbox.allowFilesystemWrite)")
        lines.append("  Network: \(p.sandbox.allowNetwork)")
        lines.append("  Process spawn: \(p.sandbox.allowProcessSpawn)")
        lines.append("")
        lines.append("Safety:")
        lines.append("  Plugin tools use ToolRegistry")
        lines.append("  Plugin cannot bypass Firewall")
        lines.append("  Plugin output is redacted")
        return lines.joined(separator: "\n")
    }
}

public enum PluginSandboxAction: String, Codable, Sendable {
    case filesystemRead, filesystemWrite, network, processSpawn
}
