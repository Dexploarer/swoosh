// SwooshMCP/MCPServerRegistry.swift — 0.8A MCP Server Registry
//
// Manages MCP server profiles, connections, discovery, and tool import.
// All imported tools go through ToolRegistry. No bypass paths.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Registry errors
// ═══════════════════════════════════════════════════════════════════

public enum MCPError: Error, Sendable {
    case serverNotFound(String)
    case serverDisabled(String)
    case serverNotConnected(String)
    case toolDenied(String)
    case resourceDenied(String)
    case promptNotPreviewed(String)
    case nonLocalBind(String)
    case neverExposable(String)
    case alreadyExists(String)
    case trustLevelInsufficient(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP server registry
// ═══════════════════════════════════════════════════════════════════

public actor MCPServerRegistry {
    private var servers: [String: MCPServerProfile] = [:]
    private var discoveredTools: [String: [MCPToolDescriptor]] = [:]
    private var discoveredResources: [String: [MCPResourceDescriptor]] = [:]
    private var discoveredPrompts: [String: [MCPPromptDescriptor]] = [:]
    private var auditLog: [MCPAuditEvent] = []
    private let redactor: MCPContentRedactor
    private let permissionMapper: MCPPermissionMapper

    public init(redactor: MCPContentRedactor = MCPContentRedactor(),
                permissionMapper: MCPPermissionMapper = MCPPermissionMapper()) {
        self.redactor = redactor; self.permissionMapper = permissionMapper
    }

    // ── Server CRUD ───────────────────────────────────────────────

    public func addServer(_ profile: MCPServerProfile) throws {
        guard servers[profile.id] == nil else { throw MCPError.alreadyExists(profile.id) }
        servers[profile.id] = profile
        appendAudit(.serverAdded(serverID: profile.id, name: profile.name))
    }

    public func enableServer(_ id: String) throws {
        guard var s = servers[id] else { throw MCPError.serverNotFound(id) }
        s.enabled = true; s.state = .configured; s.updatedAt = Date()
        servers[id] = s
        appendAudit(.serverEnabled(serverID: id))
    }

    public func disableServer(_ id: String) throws {
        guard var s = servers[id] else { throw MCPError.serverNotFound(id) }
        s.enabled = false; s.state = .disabled; s.updatedAt = Date()
        servers[id] = s
        appendAudit(.serverDisabled(serverID: id))
    }

    public func removeServer(_ id: String) throws {
        guard servers[id] != nil else { throw MCPError.serverNotFound(id) }
        servers.removeValue(forKey: id)
        discoveredTools.removeValue(forKey: id)
        discoveredResources.removeValue(forKey: id)
        discoveredPrompts.removeValue(forKey: id)
        appendAudit(.serverRemoved(serverID: id))
    }

    public func getServer(_ id: String) -> MCPServerProfile? { servers[id] }
    public func listServers() -> [MCPServerProfile] { Array(servers.values).sorted { $0.name < $1.name } }

    // ── Discovery ─────────────────────────────────────────────────

    public func registerDiscoveredTools(_ serverID: String, tools: [MCPToolDescriptor]) throws {
        guard let s = servers[serverID] else { throw MCPError.serverNotFound(serverID) }
        guard s.enabled else { throw MCPError.serverDisabled(serverID) }
        discoveredTools[serverID] = tools
        appendAudit(.discoveryCompleted(serverID: serverID, toolCount: tools.count, resourceCount: 0, promptCount: 0))
    }

    public func registerDiscoveredResources(_ serverID: String, resources: [MCPResourceDescriptor]) throws {
        guard let s = servers[serverID] else { throw MCPError.serverNotFound(serverID) }
        guard s.enabled else { throw MCPError.serverDisabled(serverID) }
        discoveredResources[serverID] = resources
    }

    public func registerDiscoveredPrompts(_ serverID: String, prompts: [MCPPromptDescriptor]) throws {
        guard let s = servers[serverID] else { throw MCPError.serverNotFound(serverID) }
        guard s.enabled else { throw MCPError.serverDisabled(serverID) }
        discoveredPrompts[serverID] = prompts
    }

    public func listTools(serverID: String) -> [MCPToolDescriptor] { discoveredTools[serverID] ?? [] }
    public func listResources(serverID: String) -> [MCPResourceDescriptor] { discoveredResources[serverID] ?? [] }
    public func listPrompts(serverID: String) -> [MCPPromptDescriptor] { discoveredPrompts[serverID] ?? [] }

    // ── Imported tool names ───────────────────────────────────────

    public func importedToolNames(serverID: String) -> [String] {
        guard let server = servers[serverID], server.enabled else { return [] }
        return (discoveredTools[serverID] ?? [])
            .filter { server.toolPolicy.isAllowed($0.name) }
            .map { $0.swooshToolName }
    }

    // ── Tool policy mutation ──────────────────────────────────────

    public func allowTool(serverID: String, toolName: String) throws {
        guard var s = servers[serverID] else { throw MCPError.serverNotFound(serverID) }
        s.toolPolicy.denylist.removeAll { $0 == toolName }
        if !s.toolPolicy.allowlist.isEmpty && !s.toolPolicy.allowlist.contains(toolName) {
            s.toolPolicy.allowlist.append(toolName)
        }
        s.updatedAt = Date()
        servers[serverID] = s
        appendAudit(.toolPolicyUpdated(serverID: serverID, toolName: toolName, action: "allow"))
    }

    public func denyTool(serverID: String, toolName: String) throws {
        guard var s = servers[serverID] else { throw MCPError.serverNotFound(serverID) }
        if !s.toolPolicy.denylist.contains(toolName) { s.toolPolicy.denylist.append(toolName) }
        s.updatedAt = Date()
        servers[serverID] = s
        appendAudit(.toolPolicyUpdated(serverID: serverID, toolName: toolName, action: "deny"))
    }

    // ── Risk classification ───────────────────────────────────────

    public func classifyToolRisk(serverID: String, toolName: String) -> ToolRisk {
        guard let server = servers[serverID] else { return .medium }
        if server.trustLevel == .untrusted { return max(server.toolPolicy.defaultRisk, .medium) }
        return permissionMapper.classifyRisk(toolName)
    }

    // ── Resource read gating ──────────────────────────────────────

    public func isResourceReadAllowed(serverID: String, uri: String) throws -> Bool {
        guard let s = servers[serverID] else { throw MCPError.serverNotFound(serverID) }
        guard s.enabled else { throw MCPError.serverDisabled(serverID) }
        if s.resourcePolicy.isURIDenied(uri) { return false }
        return s.resourcePolicy.allowResourceReads
    }

    // ── Swoosh MCP server exposure ────────────────────────────────

    public func validateExposure(_ config: SwooshMCPServerConfiguration) throws {
        guard config.isLocalOnly else { throw MCPError.nonLocalBind(config.bindHost) }
        for tool in config.exposedToolAllowlist {
            if SwooshMCPServerConfiguration.neverExpose.contains(tool) {
                throw MCPError.neverExposable(tool)
            }
        }
    }

    // ── Redaction ─────────────────────────────────────────────────

    public func redactResult(_ text: String) -> String { redactor.redact(text) }

    // ── Audit ─────────────────────────────────────────────────────

    private func appendAudit(_ event: MCPAuditEvent) { auditLog.append(event) }
    public func getAuditLog() -> [MCPAuditEvent] { auditLog }

    // ── /why ──────────────────────────────────────────────────────

    public func whyExplanation(serverID: String, toolName: String? = nil) -> String {
        guard let s = servers[serverID] else { return "MCP server not found." }
        var lines: [String] = []
        lines.append("MCP Server: \(s.name)")
        lines.append("Trust: \(s.trustLevel.rawValue)")
        lines.append("State: \(s.state.rawValue)")
        lines.append("Enabled: \(s.enabled)")
        if let t = toolName {
            let risk = classifyToolRisk(serverID: serverID, toolName: t)
            lines.append("Tool: \(t)")
            lines.append("Risk: \(risk.rawValue)")
            lines.append("Approval required: \(s.toolPolicy.requireUserApprovalForAllCalls)")
        }
        lines.append("")
        lines.append("Safety:")
        lines.append("  Tool calls go through ToolRegistry")
        lines.append("  Firewall permissions are enforced")
        lines.append("  Results are redacted and truncated")
        lines.append("  Results are not written to memory automatically")
        lines.append("  Server cannot approve its own actions")
        return lines.joined(separator: "\n")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP audit events
// ═══════════════════════════════════════════════════════════════════

public struct MCPAuditEvent: Codable, Sendable {
    public let kind: MCPAuditEventKind
    public let serverID: String
    public let message: String
    public let createdAt: Date

    public init(kind: MCPAuditEventKind, serverID: String, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.serverID = serverID; self.message = message; self.createdAt = createdAt
    }

    static func serverAdded(serverID: String, name: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .serverAdded, serverID: serverID, message: "Server added: \(name)")
    }
    static func serverEnabled(serverID: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .serverEnabled, serverID: serverID, message: "Server enabled")
    }
    static func serverDisabled(serverID: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .serverDisabled, serverID: serverID, message: "Server disabled")
    }
    static func serverRemoved(serverID: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .serverRemoved, serverID: serverID, message: "Server removed")
    }
    static func discoveryCompleted(serverID: String, toolCount: Int, resourceCount: Int, promptCount: Int) -> MCPAuditEvent {
        MCPAuditEvent(kind: .discoveryCompleted, serverID: serverID,
                      message: "Discovered \(toolCount) tools, \(resourceCount) resources, \(promptCount) prompts")
    }
    static func toolPolicyUpdated(serverID: String, toolName: String, action: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .toolPolicyUpdated, serverID: serverID, message: "Tool \(toolName): \(action)")
    }
    static func toolCallStarted(serverID: String, toolName: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .toolCallStarted, serverID: serverID, message: "Tool call: \(toolName)")
    }
    static func toolCallCompleted(serverID: String, toolName: String) -> MCPAuditEvent {
        MCPAuditEvent(kind: .toolCallCompleted, serverID: serverID, message: "Tool call completed: \(toolName)")
    }
}

public enum MCPAuditEventKind: String, Codable, Sendable {
    case serverAdded, serverEnabled, serverDisabled, serverRemoved
    case discoveryCompleted, toolPolicyUpdated
    case toolCallStarted, toolCallCompleted, toolCallFailed
    case resourceRead, promptPreviewed, promptApplied
    case exposeStarted, exposeStopped
    case swiftWrappersGenerated
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Swift wrapper generator
// ═══════════════════════════════════════════════════════════════════

public struct MCPSwiftWrapperGenerator: Sendable {
    public init() {}

    public func generate(serverID: String, serverName: String, tools: [MCPToolDescriptor]) -> String {
        var lines: [String] = []
        lines.append("// Generated by Swoosh MCP — \(serverName)")
        lines.append("// These wrappers call ToolRegistry, NOT the MCP server directly.")
        lines.append("// Do not edit manually.")
        lines.append("")
        lines.append("import Foundation")
        lines.append("import SwooshTools")
        lines.append("")
        lines.append("public struct \(safeName(serverName))MCP {")
        lines.append("    private let callTool: (String, [String: String]) async throws -> String")
        lines.append("")
        lines.append("    public init(callTool: @escaping (String, [String: String]) async throws -> String) {")
        lines.append("        self.callTool = callTool")
        lines.append("    }")
        lines.append("")
        for tool in tools {
            lines.append("    /// \(tool.description ?? tool.name)")
            lines.append("    public func \(safeFuncName(tool.name))() async throws -> String {")
            lines.append("        try await callTool(\"mcp.\(serverID).\(tool.name)\", [:])")
            lines.append("    }")
            lines.append("")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private func safeFuncName(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: ".", with: "_")
    }
}
