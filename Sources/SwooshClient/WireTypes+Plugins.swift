// SwooshClient/WireTypes+Plugins.swift — 0.4A Plugin catalog wire types
//
// Wire format for `GET /api/plugins`, `GET /api/plugins/{id}`, and the
// install/enable/disable/uninstall mutations. Lossless re-encoding of
// `SwooshPlugins.PluginManifest` so iOS can render the plugin catalog
// without depending on the runtime module.

import Foundation

/// One plugin tool entry, in wire form. Lossless re-encoding of
/// `PluginToolManifest` so the iOS app can render the agent's installed
/// plugin catalog without depending on `SwooshPlugins`.
public struct PluginToolSummary: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let permission: String
    public let risk: String
    public let requiresApproval: Bool

    public init(name: String, description: String, permission: String, risk: String, requiresApproval: Bool) {
        self.name = name; self.description = description
        self.permission = permission; self.risk = risk
        self.requiresApproval = requiresApproval
    }
}

/// One installed plugin in wire form. `kind` is one of `"swift"`,
/// `"executable"`, `"wasm"`, `"mcpBridge"`.
public struct PluginSummary: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let author: String?
    public let kind: String
    public let enabled: Bool
    public let requestedPermissions: [String]
    public let tools: [PluginToolSummary]
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, name: String, version: String, description: String?,
                author: String?, kind: String, enabled: Bool,
                requestedPermissions: [String], tools: [PluginToolSummary],
                createdAt: Date, updatedAt: Date) {
        self.id = id; self.name = name; self.version = version
        self.description = description; self.author = author; self.kind = kind
        self.enabled = enabled
        self.requestedPermissions = requestedPermissions; self.tools = tools
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct PluginsResponse: Codable, Sendable, Equatable {
    public let plugins: [PluginSummary]

    public init(plugins: [PluginSummary]) { self.plugins = plugins }
}

public struct PluginEventSummary: Codable, Sendable, Equatable {
    public let kind: String
    public let message: String
    public let createdAt: Date

    public init(kind: String, message: String, createdAt: Date) {
        self.kind = kind; self.message = message; self.createdAt = createdAt
    }
}

public struct PluginDetailResponse: Codable, Sendable, Equatable {
    public let plugin: PluginSummary
    /// Permissions the firewall is currently granting on this plugin's
    /// behalf — i.e. the perms it added on top of the baseline.
    public let grantedPermissions: [String]
    /// Most-recent plugin events, newest last.
    public let auditTail: [PluginEventSummary]

    public init(plugin: PluginSummary, grantedPermissions: [String], auditTail: [PluginEventSummary]) {
        self.plugin = plugin
        self.grantedPermissions = grantedPermissions
        self.auditTail = auditTail
    }
}

/// Install request body. `sourcePath` is a directory on the daemon's
/// filesystem that contains a `manifest.json` (and any kind-specific
/// files — `main.sh`, `plugin.wasm`, etc.). The host copies the directory
/// into `~/.swoosh/plugins/<id>/`.
public struct PluginInstallRequest: Codable, Sendable, Equatable {
    public let sourcePath: String

    public init(sourcePath: String) { self.sourcePath = sourcePath }
}

public struct PluginMutationResponse: Codable, Sendable, Equatable {
    public let plugin: PluginSummary
    public let message: String

    public init(plugin: PluginSummary, message: String) {
        self.plugin = plugin
        self.message = message
    }
}
