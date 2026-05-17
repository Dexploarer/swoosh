// SwooshPlugins/PluginTypes.swift — 0.8A Plugin Foundation
//
// Plugins are local extensions to Swoosh.
// Plugins are discovered, inspected, and approved before enabling.
// Plugin tools register through ToolRegistry. No direct bypass.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin manifest
// ═══════════════════════════════════════════════════════════════════

public struct PluginManifest: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var version: String
    public var description: String?
    public var author: String?
    public var kind: PluginKind
    public var entrypoint: PluginEntrypoint
    public var requestedPermissions: [String]
    public var tools: [PluginToolManifest]
    public var sandbox: PluginSandboxPolicy
    public var enabled: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String, name: String, version: String, description: String? = nil,
        author: String? = nil, kind: PluginKind = .swift,
        entrypoint: PluginEntrypoint = .swiftModule(""),
        requestedPermissions: [String] = [], tools: [PluginToolManifest] = [],
        sandbox: PluginSandboxPolicy = .safeDefault, enabled: Bool = false,
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.name = name; self.version = version
        self.description = description; self.author = author; self.kind = kind
        self.entrypoint = entrypoint; self.requestedPermissions = requestedPermissions
        self.tools = tools; self.sandbox = sandbox; self.enabled = enabled
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum PluginKind: String, Codable, Sendable {
    case swift, executable, wasm, mcpBridge
}

public enum PluginEntrypoint: Codable, Sendable {
    case swiftModule(String)
    case executable(path: String, arguments: [String])
    case wasm(path: String)
    case mcpServer(serverID: String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin tool manifest
// ═══════════════════════════════════════════════════════════════════

public struct PluginToolManifest: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let risk: ToolRisk
    public let requiresApproval: Bool

    public init(id: String = UUID().uuidString, name: String, description: String,
                risk: ToolRisk = .medium, requiresApproval: Bool = true) {
        self.id = id; self.name = name; self.description = description
        self.risk = risk; self.requiresApproval = requiresApproval
    }

    public var swooshToolName: String { "plugin.\(name)" }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin sandbox policy
// ═══════════════════════════════════════════════════════════════════

public struct PluginSandboxPolicy: Codable, Sendable {
    public let allowFilesystemRead: Bool
    public let allowFilesystemWrite: Bool
    public let allowNetwork: Bool
    public let allowProcessSpawn: Bool
    public let allowedRoots: [String]
    public let maxOutputBytes: Int
    public let timeoutSeconds: Int

    public static let safeDefault = PluginSandboxPolicy(
        allowFilesystemRead: false, allowFilesystemWrite: false,
        allowNetwork: false, allowProcessSpawn: false,
        allowedRoots: [], maxOutputBytes: 64_000, timeoutSeconds: 30
    )

    public init(allowFilesystemRead: Bool, allowFilesystemWrite: Bool,
                allowNetwork: Bool, allowProcessSpawn: Bool,
                allowedRoots: [String], maxOutputBytes: Int, timeoutSeconds: Int) {
        self.allowFilesystemRead = allowFilesystemRead
        self.allowFilesystemWrite = allowFilesystemWrite
        self.allowNetwork = allowNetwork; self.allowProcessSpawn = allowProcessSpawn
        self.allowedRoots = allowedRoots; self.maxOutputBytes = maxOutputBytes
        self.timeoutSeconds = timeoutSeconds
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin audit event
// ═══════════════════════════════════════════════════════════════════

public struct PluginAuditEvent: Codable, Sendable {
    public let kind: PluginAuditEventKind
    public let pluginID: String
    public let message: String
    public let createdAt: Date

    public init(kind: PluginAuditEventKind, pluginID: String, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.pluginID = pluginID; self.message = message; self.createdAt = createdAt
    }
}

public enum PluginAuditEventKind: String, Codable, Sendable {
    case discovered, inspected, enableRequested, enabled, disabled
    case toolRegistered, toolCallStarted, toolCallCompleted, toolCallFailed
    case sandboxViolation
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin content redactor
// ═══════════════════════════════════════════════════════════════════

public struct PluginContentRedactor: Sendable {
    private static let sensitivePatterns = [
        "-----BEGIN", "PRIVATE KEY", "sk_", "xprv", "xpub",
        "seed:", "mnemonic:", "cookie:", "session_token",
        "password:", "secret:", "Bearer ", "api_key:", "token:",
    ]

    public init() {}

    public func redact(_ text: String) -> String {
        var v = text
        for p in Self.sensitivePatterns {
            if v.contains(p) { v = v.replacingOccurrences(of: p, with: "[REDACTED]") }
        }
        return v
    }
}
