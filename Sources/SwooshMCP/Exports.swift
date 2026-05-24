// SwooshMCP/Exports.swift — MCP server profiles, transports, policies, descriptors — 0.8B
//
// MCP server profiles, transports, policies, descriptors, and trust levels.
// Imported MCP tools are UNTRUSTED by default and go through ToolRegistry.
// No bypass of Firewall, ApprovalCenter, or audit.
//
// `MCPContentRedactor` consumes the project-wide sensitive-substring list
// from `SwooshTools.SensitivePatterns.strings` — see
// `SwooshTools/SensitivePatterns.swift` for the canonical patterns.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP server profile
// ═══════════════════════════════════════════════════════════════════

public struct MCPServerProfile: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var description: String?
    public var transport: MCPTransportConfiguration
    public var state: MCPServerState
    public var trustLevel: MCPTrustLevel
    public var enabled: Bool
    public var toolPolicy: MCPToolPolicy
    public var resourcePolicy: MCPResourcePolicy
    public var promptPolicy: MCPPromptPolicy
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String, name: String, description: String? = nil,
        transport: MCPTransportConfiguration, state: MCPServerState = .configured,
        trustLevel: MCPTrustLevel = .untrusted, enabled: Bool = false,
        toolPolicy: MCPToolPolicy = .safeDefault,
        resourcePolicy: MCPResourcePolicy = .safeDefault,
        promptPolicy: MCPPromptPolicy = .safeDefault,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.name = name; self.description = description
        self.transport = transport; self.state = state; self.trustLevel = trustLevel
        self.enabled = enabled; self.toolPolicy = toolPolicy
        self.resourcePolicy = resourcePolicy; self.promptPolicy = promptPolicy
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum MCPServerState: String, Codable, Sendable {
    case configured, connecting, connected, disconnected, failed, disabled
}

public enum MCPTrustLevel: String, Codable, Sendable {
    case untrusted, localTrusted, userApproved, organizationApproved
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Transport
// ═══════════════════════════════════════════════════════════════════

public enum MCPTransportConfiguration: Codable, Sendable {
    case stdio(MCPStdioConfiguration)
    case http(MCPHTTPConfiguration)
}

public struct MCPStdioConfiguration: Codable, Sendable {
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String?
    /// Secret refs (Keychain IDs), never raw values
    public let environmentSecretRefs: [String: String]

    public init(command: String, arguments: [String] = [], workingDirectory: String? = nil,
                environmentSecretRefs: [String: String] = [:]) {
        self.command = command; self.arguments = arguments
        self.workingDirectory = workingDirectory; self.environmentSecretRefs = environmentSecretRefs
    }
}

public struct MCPHTTPConfiguration: Codable, Sendable {
    public let baseURL: String
    public let authorizationSecretRef: String?
    public let localOnly: Bool

    public init(baseURL: String, authorizationSecretRef: String? = nil, localOnly: Bool = true) {
        self.baseURL = baseURL; self.authorizationSecretRef = authorizationSecretRef
        self.localOnly = localOnly
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tool policy
// ═══════════════════════════════════════════════════════════════════

public struct MCPToolPolicy: Codable, Sendable {
    public var importTools: Bool
    public var defaultRisk: ToolRisk
    public var allowlist: [String]
    public var denylist: [String]
    public var maxResultBytes: Int
    public var requireUserApprovalForAllCalls: Bool

    public static let safeDefault = MCPToolPolicy(
        importTools: true, defaultRisk: .medium, allowlist: [], denylist: [],
        maxResultBytes: 64_000, requireUserApprovalForAllCalls: true
    )

    public init(importTools: Bool, defaultRisk: ToolRisk, allowlist: [String],
                denylist: [String], maxResultBytes: Int, requireUserApprovalForAllCalls: Bool) {
        self.importTools = importTools; self.defaultRisk = defaultRisk
        self.allowlist = allowlist; self.denylist = denylist
        self.maxResultBytes = maxResultBytes; self.requireUserApprovalForAllCalls = requireUserApprovalForAllCalls
    }

    public func isAllowed(_ toolName: String) -> Bool {
        if denylist.contains(toolName) { return false }
        if !allowlist.isEmpty { return allowlist.contains(toolName) }
        return true
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Resource policy
// ═══════════════════════════════════════════════════════════════════

public struct MCPResourcePolicy: Codable, Sendable {
    public var importResources: Bool
    public var allowResourceReads: Bool
    public var maxResourceBytes: Int
    public var requireApprovalForResourceRead: Bool
    public var denyURIPatterns: [String]

    public static let safeDefault = MCPResourcePolicy(
        importResources: true, allowResourceReads: true, maxResourceBytes: 256_000,
        requireApprovalForResourceRead: true,
        denyURIPatterns: ["*cookie*", "*secret*", "*private_key*", "*.env*"]
    )

    public init(importResources: Bool, allowResourceReads: Bool, maxResourceBytes: Int,
                requireApprovalForResourceRead: Bool, denyURIPatterns: [String]) {
        self.importResources = importResources; self.allowResourceReads = allowResourceReads
        self.maxResourceBytes = maxResourceBytes
        self.requireApprovalForResourceRead = requireApprovalForResourceRead
        self.denyURIPatterns = denyURIPatterns
    }

    public func isURIDenied(_ uri: String) -> Bool {
        let lower = uri.lowercased()
        return denyURIPatterns.contains { pattern in
            let p = pattern.lowercased().replacingOccurrences(of: "*", with: "")
            return lower.contains(p)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Prompt policy
// ═══════════════════════════════════════════════════════════════════

public struct MCPPromptPolicy: Codable, Sendable {
    public var importPrompts: Bool
    public var allowPromptUse: Bool
    public var requireUserSelection: Bool
    public var requirePreviewBeforeUse: Bool

    public static let safeDefault = MCPPromptPolicy(
        importPrompts: true, allowPromptUse: true,
        requireUserSelection: true, requirePreviewBeforeUse: true
    )

    public init(importPrompts: Bool, allowPromptUse: Bool,
                requireUserSelection: Bool, requirePreviewBeforeUse: Bool) {
        self.importPrompts = importPrompts; self.allowPromptUse = allowPromptUse
        self.requireUserSelection = requireUserSelection
        self.requirePreviewBeforeUse = requirePreviewBeforeUse
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Discovered descriptors
// ═══════════════════════════════════════════════════════════════════

public struct MCPToolDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchemaJSON: String?
    public let discoveredAt: Date

    public init(id: String = UUID().uuidString, serverID: String, name: String,
                title: String? = nil, description: String? = nil,
                inputSchemaJSON: String? = nil, discoveredAt: Date = Date()) {
        self.id = id; self.serverID = serverID; self.name = name
        self.title = title; self.description = description
        self.inputSchemaJSON = inputSchemaJSON; self.discoveredAt = discoveredAt
    }

    public var swooshToolName: String { "mcp.\(serverID).\(name)" }
}

public struct MCPResourceDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let uri: String
    public let name: String?
    public let title: String?
    public let description: String?
    public let mimeType: String?
    public let discoveredAt: Date

    public init(id: String = UUID().uuidString, serverID: String, uri: String,
                name: String? = nil, title: String? = nil, description: String? = nil,
                mimeType: String? = nil, discoveredAt: Date = Date()) {
        self.id = id; self.serverID = serverID; self.uri = uri
        self.name = name; self.title = title; self.description = description
        self.mimeType = mimeType; self.discoveredAt = discoveredAt
    }
}

public struct MCPPromptDescriptor: Codable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let name: String
    public let title: String?
    public let description: String?
    public let discoveredAt: Date

    public init(id: String = UUID().uuidString, serverID: String, name: String,
                title: String? = nil, description: String? = nil, discoveredAt: Date = Date()) {
        self.id = id; self.serverID = serverID; self.name = name
        self.title = title; self.description = description; self.discoveredAt = discoveredAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Permission/approval mapping
// ═══════════════════════════════════════════════════════════════════

public struct MCPPermissionMapper: Sendable {
    public init() {}

    /// Heuristic risk classification from MCP tool name
    public func classifyRisk(_ toolName: String) -> ToolRisk {
        let lower = toolName.lowercased()
        let readPatterns = ["read", "list", "get", "search", "find", "status", "info", "describe", "show"]
        let writePatterns = ["write", "create", "update", "delete", "patch", "put", "remove", "modify"]
        let dangerPatterns = ["send", "post", "publish", "broadcast", "exec", "run", "shell", "command", "deploy"]

        if dangerPatterns.contains(where: { lower.contains($0) }) { return .critical }
        if writePatterns.contains(where: { lower.contains($0) }) { return .high }
        if readPatterns.contains(where: { lower.contains($0) }) { return .readOnly }
        return .medium
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Swoosh as MCP server config
// ═══════════════════════════════════════════════════════════════════

public struct SwooshMCPServerConfiguration: Codable, Sendable {
    public let enabled: Bool
    public let localOnly: Bool
    public let bindHost: String
    public let port: Int?
    public let exposedToolAllowlist: [String]
    public let exposeResources: Bool
    public let exposePrompts: Bool

    /// Tools that must never be exposed
    public static let neverExpose: Set<String> = [
        "approval.resolve", "workflow.approve_gate",
        "file.write", "file.patch", "file.delete",
        "git.commit", "git.push",
        "worker.start", "trigger.arm",
        "evm.tx_request_signature", "evm.tx_broadcast_signed",
        "solana.tx_request_signature", "solana.tx_send_signed",
    ]

    public static let safeDefault = SwooshMCPServerConfiguration(
        enabled: false, localOnly: true, bindHost: "127.0.0.1", port: nil,
        exposedToolAllowlist: [
            "core.status", "core.list_tools", "memory.list_approved",
            "permissions.summary", "workflow.list_drafts", "workflow.list_runs",
            "board.card.list", "board.card.get",
        ],
        exposeResources: false, exposePrompts: false
    )

    public init(enabled: Bool, localOnly: Bool, bindHost: String, port: Int?,
                exposedToolAllowlist: [String], exposeResources: Bool, exposePrompts: Bool) {
        self.enabled = enabled; self.localOnly = localOnly; self.bindHost = bindHost
        self.port = port; self.exposedToolAllowlist = exposedToolAllowlist
        self.exposeResources = exposeResources; self.exposePrompts = exposePrompts
    }

    public func isToolExposable(_ toolName: String) -> Bool {
        if Self.neverExpose.contains(toolName) { return false }
        return exposedToolAllowlist.contains(toolName)
    }

    public var isLocalOnly: Bool {
        localOnly && (bindHost == "127.0.0.1" || bindHost == "localhost" || bindHost == "::1")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP content redactor
// ═══════════════════════════════════════════════════════════════════

public struct MCPContentRedactor: Sendable {
    private let maxBytes: Int

    public init(maxBytes: Int = 64_000) { self.maxBytes = maxBytes }

    public func redact(_ text: String) -> String {
        // Pattern list is shared with `SwooshPlugins.PluginContentRedactor`
        // via `SwooshTools.SensitivePatterns.strings` — adding a new token
        // in one place now covers both redactors.
        var v = text
        for pattern in SensitivePatterns.strings where v.contains(pattern) {
            v = v.replacingOccurrences(of: pattern, with: "[REDACTED]")
        }
        if v.utf8.count > maxBytes { v = String(v.prefix(maxBytes)) + "…[truncated]" }
        return v
    }
}
