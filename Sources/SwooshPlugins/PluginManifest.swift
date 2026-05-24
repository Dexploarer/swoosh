// SwooshPlugins/PluginManifest.swift — Plugin manifest schema + elizaOS-compat decoding — 0.9A
//
// `PluginManifest` is the cross-platform schema for a Swoosh plugin: id,
// version, kind, entrypoint, requested permissions, declared tools,
// sandbox limits, dependencies, priority. Trust contract reminder:
//
//   1. Manifests are inspected before enabling. `validate()` rejects
//      unknown permissions and rejects tools whose permission isn't in
//      the plugin's `requestedPermissions` set.
//   2. Each plugin tool declares an ordinary `SwooshPermission` and goes
//      through `ToolRegistry.execute`, which calls the firewall on its own
//      permission. No tool bypass.
//   3. Enabling a plugin (humanOnly admin permission `pluginEnable`) grants
//      that plugin's requested permissions to the firewall; disabling
//      revokes them — minus anything still claimed by other enabled
//      plugins or already in the baseline grant set. The actual
//      grant/revoke bookkeeping lives in `SwooshPluginRuntime.PluginHost`
//      so the cross-platform types stay free of firewall dependencies.
//
// Custom Codable on `PluginManifest` is intentional: it accepts the
// elizaOS-style `actions` field as an alias for `tools` so manifests are
// portable across the two runtimes. Output always serialises as the
// canonical `tools` field.

import Foundation

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
    /// Other plugins this plugin requires to be installed + enabled. The
    /// host refuses to enable a plugin whose dependencies are missing.
    /// Mirrors elizaOS's `plugin.dependencies` field for portability.
    public var dependencies: [String]
    /// Optional ordering hint — higher priorities load first. Used for
    /// dependency-resolution stability and planner ranking. Defaults to 0.
    public var priority: Int

    public init(
        id: String, name: String, version: String, description: String? = nil,
        author: String? = nil, kind: PluginKind = .swift,
        entrypoint: PluginEntrypoint = .swiftModule(""),
        requestedPermissions: [String] = [], tools: [PluginToolManifest] = [],
        sandbox: PluginSandboxPolicy = .safeDefault, enabled: Bool = false,
        createdAt: Date = Date(), updatedAt: Date = Date(),
        dependencies: [String] = [], priority: Int = 0
    ) {
        self.id = id; self.name = name; self.version = version
        self.description = description; self.author = author; self.kind = kind
        self.entrypoint = entrypoint; self.requestedPermissions = requestedPermissions
        self.tools = tools; self.sandbox = sandbox; self.enabled = enabled
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.dependencies = dependencies; self.priority = priority
    }

    // Custom decoding so an elizaOS-style manifest using `actions` in place
    // of `tools` still loads. The field is always serialised as `tools` —
    // `actions` is read-only convenience. Other fields default when missing
    // so backward compatibility with pre-0.8C manifests is preserved.
    private enum CodingKeys: String, CodingKey {
        case id, name, version, description, author, kind, entrypoint
        case requestedPermissions, tools, actions, sandbox, enabled
        case createdAt, updatedAt, dependencies, priority
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(String.self, forKey: .version)
        self.description = c.decodeOptional(String.self, forKey: .description)
        self.author = c.decodeOptional(String.self, forKey: .author)
        self.kind = c.decodeOrDefault(PluginKind.self, forKey: .kind, default: .swift)
        self.entrypoint = c.decodeOrDefault(
            PluginEntrypoint.self, forKey: .entrypoint, default: .swiftModule("")
        )
        self.requestedPermissions = c.decodeOrDefault(
            [String].self, forKey: .requestedPermissions, default: []
        )
        let tools = c.decodeOrDefault([PluginToolManifest].self, forKey: .tools, default: [])
        let actions = c.decodeOrDefault([PluginToolManifest].self, forKey: .actions, default: [])
        self.tools = tools.isEmpty ? actions : tools
        self.sandbox = c.decodeOrDefault(
            PluginSandboxPolicy.self, forKey: .sandbox, default: .safeDefault
        )
        self.enabled = c.decodeOrDefault(Bool.self, forKey: .enabled, default: false)
        self.createdAt = c.decodeOrDefault(Date.self, forKey: .createdAt, default: Date())
        self.updatedAt = c.decodeOrDefault(Date.self, forKey: .updatedAt, default: Date())
        self.dependencies = c.decodeOrDefault([String].self, forKey: .dependencies, default: [])
        self.priority = c.decodeOrDefault(Int.self, forKey: .priority, default: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encode(kind, forKey: .kind)
        try c.encode(entrypoint, forKey: .entrypoint)
        try c.encode(requestedPermissions, forKey: .requestedPermissions)
        try c.encode(tools, forKey: .tools)
        try c.encode(sandbox, forKey: .sandbox)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        if !dependencies.isEmpty { try c.encode(dependencies, forKey: .dependencies) }
        if priority != 0 { try c.encode(priority, forKey: .priority) }
    }
}

// MARK: - Plugin kind

public enum PluginKind: String, Codable, Sendable {
    case swift, executable, wasm, mcpBridge
}

// MARK: - Plugin entrypoint

public enum PluginEntrypoint: Codable, Sendable {
    case swiftModule(String)
    case executable(path: String, arguments: [String])
    /// Wasm module with the linear-memory ABI — the host writes args into
    /// the module's linear memory and invokes an exported function whose
    /// name matches the tool's bare segment (e.g. `wasm.add` → export
    /// `add`). No WASI imports. Best for pure number-crunching tools and
    /// tiny demos.
    case wasm(path: String)
    /// Wasm module with the WASI Preview 1 ABI. The host invokes `_start`
    /// with argv `[plugin-id, tool-name, args-json]`, captures stdout as
    /// the response, and treats a non-zero WASI exit code as failure.
    /// The module imports `wasi_snapshot_preview1` for `fd_write` (and
    /// optionally `fd_read`); no host filesystem or env is exposed.
    case wasiWasm(path: String)
    case mcpServer(serverID: String)
}
