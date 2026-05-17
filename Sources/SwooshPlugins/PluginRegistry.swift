// SwooshPlugins/PluginRegistry.swift — 0.8A Plugin Registry

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin errors
// ═══════════════════════════════════════════════════════════════════

public enum PluginError: Error, Sendable {
    case notFound(String)
    case alreadyExists(String)
    case notEnabled(String)
    case sandboxViolation(String)
    case toolNotRegistered(String)
    case approvalRequired(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin registry
// ═══════════════════════════════════════════════════════════════════

public actor PluginRegistry {
    private var plugins: [String: PluginManifest] = [:]
    private var registeredTools: [String: String] = [:]  // toolName → pluginID
    private var auditLog: [PluginAuditEvent] = []
    private let redactor: PluginContentRedactor

    public init(redactor: PluginContentRedactor = PluginContentRedactor()) {
        self.redactor = redactor
    }

    // ── Registration ──────────────────────────────────────────────

    public func register(_ manifest: PluginManifest) throws {
        guard plugins[manifest.id] == nil else { throw PluginError.alreadyExists(manifest.id) }
        plugins[manifest.id] = manifest
        appendAudit(.init(kind: .discovered, pluginID: manifest.id, message: "Plugin registered: \(manifest.name)"))
    }

    public func inspect(_ id: String) throws -> PluginManifest {
        guard let p = plugins[id] else { throw PluginError.notFound(id) }
        appendAudit(.init(kind: .inspected, pluginID: id, message: "Plugin inspected"))
        return p
    }

    public func enable(_ id: String) throws {
        guard var p = plugins[id] else { throw PluginError.notFound(id) }
        p.enabled = true; p.updatedAt = Date()
        plugins[id] = p
        // Register plugin tools
        for tool in p.tools {
            registeredTools[tool.swooshToolName] = id
            appendAudit(.init(kind: .toolRegistered, pluginID: id, message: "Tool registered: \(tool.swooshToolName)"))
        }
        appendAudit(.init(kind: .enabled, pluginID: id, message: "Plugin enabled"))
    }

    public func disable(_ id: String) throws {
        guard var p = plugins[id] else { throw PluginError.notFound(id) }
        p.enabled = false; p.updatedAt = Date()
        plugins[id] = p
        // Unregister tools
        for tool in p.tools { registeredTools.removeValue(forKey: tool.swooshToolName) }
        appendAudit(.init(kind: .disabled, pluginID: id, message: "Plugin disabled"))
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

    public func validateSandbox(pluginID: String, action: PluginSandboxAction) throws -> Bool {
        guard let p = plugins[pluginID] else { throw PluginError.notFound(pluginID) }
        switch action {
        case .filesystemRead:
            if !p.sandbox.allowFilesystemRead {
                appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Filesystem read denied"))
                return false
            }
        case .filesystemWrite:
            if !p.sandbox.allowFilesystemWrite {
                appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Filesystem write denied"))
                return false
            }
        case .network:
            if !p.sandbox.allowNetwork {
                appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Network denied"))
                return false
            }
        case .processSpawn:
            if !p.sandbox.allowProcessSpawn {
                appendAudit(.init(kind: .sandboxViolation, pluginID: pluginID, message: "Process spawn denied"))
                return false
            }
        }
        return true
    }

    // ── Redaction ─────────────────────────────────────────────────

    public func redactOutput(_ text: String) -> String { redactor.redact(text) }

    // ── Audit ─────────────────────────────────────────────────────

    private func appendAudit(_ event: PluginAuditEvent) { auditLog.append(event) }
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
