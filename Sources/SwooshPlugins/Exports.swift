// SwooshPlugins/Exports.swift — 0.8B Plugin Foundation
//
// Plugins are local extensions to Swoosh — Swift, executable, wasm, or
// mcpBridge — that publish new tools into the agent's `ToolRegistry`.
//
// Trust contract:
//   1. Manifests are inspected before enabling. `validate()` rejects unknown
//      permissions and rejects tools whose permission isn't in the plugin's
//      `requestedPermissions` set.
//   2. Each plugin tool declares an ordinary `SwooshPermission` and goes
//      through `ToolRegistry.execute`, which calls the firewall on its own
//      permission. No tool bypass.
//   3. Enabling a plugin (humanOnly admin permission `pluginEnable`) grants
//      that plugin's requested permissions to the firewall; disabling
//      revokes them — minus anything still claimed by other enabled plugins
//      or already in the baseline grant set. The actual grant/revoke
//      bookkeeping lives in `SwooshPluginRuntime.PluginHost` so the
//      cross-platform types stay free of firewall dependencies.

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
        self.description = try? c.decode(String.self, forKey: .description)
        self.author = try? c.decode(String.self, forKey: .author)
        self.kind = (try? c.decode(PluginKind.self, forKey: .kind)) ?? .swift
        self.entrypoint = (try? c.decode(PluginEntrypoint.self, forKey: .entrypoint))
            ?? .swiftModule("")
        self.requestedPermissions = (try? c.decode([String].self, forKey: .requestedPermissions)) ?? []
        let tools = (try? c.decode([PluginToolManifest].self, forKey: .tools)) ?? []
        let actions = (try? c.decode([PluginToolManifest].self, forKey: .actions)) ?? []
        self.tools = tools.isEmpty ? actions : tools
        self.sandbox = (try? c.decode(PluginSandboxPolicy.self, forKey: .sandbox)) ?? .safeDefault
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        self.dependencies = (try? c.decode([String].self, forKey: .dependencies)) ?? []
        self.priority = (try? c.decode(Int.self, forKey: .priority)) ?? 0
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

public enum PluginKind: String, Codable, Sendable {
    case swift, executable, wasm, mcpBridge
}

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

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugin tool manifest
// ═══════════════════════════════════════════════════════════════════

public struct PluginToolManifest: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    /// Permission the tool's bridge calls require via the firewall.
    /// Must appear in the parent plugin's `requestedPermissions` list — that
    /// invariant is checked by `PluginManifest.validate()` at install time.
    public let permission: SwooshPermission
    public let risk: ToolRisk
    public let requiresApproval: Bool
    /// elizaOS-style alias names that match the same intent. The planner
    /// can surface these alongside the canonical `name` to widen tool
    /// selection. Optional — left empty by tools that only have one name.
    public let similes: [String]
    /// Free-form example usages, shown to the model so it learns when to
    /// pick this tool. elizaOS uses paired `{user, agent}` messages; we
    /// accept the simpler "one line per example" form here and let
    /// authors paste the eliza shape verbatim if they prefer.
    public let examples: [String]
    /// Categorisation tags. Used for filtering, routing hints, and the
    /// planner's compressed catalog view.
    public let tags: [String]

    public init(id: String = UUID().uuidString, name: String, description: String,
                permission: SwooshPermission = .toolRead,
                risk: ToolRisk = .medium, requiresApproval: Bool = true,
                similes: [String] = [], examples: [String] = [], tags: [String] = []) {
        self.id = id; self.name = name; self.description = description
        self.permission = permission
        self.risk = risk; self.requiresApproval = requiresApproval
        self.similes = similes; self.examples = examples; self.tags = tags
    }

    public var swooshToolName: String { "plugin.\(name)" }

    // Backward-compat decoding: manifests written before the typed
    // `permission` field existed should still load, defaulting to `.toolRead`
    // (the safest read-only permission). Validation will then reject the
    // plugin if `.toolRead` isn't in `requestedPermissions`.
    private enum CodingKeys: String, CodingKey {
        case id, name, description, permission, risk, requiresApproval
        case similes, examples, tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decode(String.self, forKey: .description)
        self.permission = (try? c.decode(SwooshPermission.self, forKey: .permission)) ?? .toolRead
        self.risk = (try? c.decode(ToolRisk.self, forKey: .risk)) ?? .medium
        self.requiresApproval = (try? c.decode(Bool.self, forKey: .requiresApproval)) ?? true
        self.similes = (try? c.decode([String].self, forKey: .similes)) ?? []
        self.examples = (try? c.decode([String].self, forKey: .examples)) ?? []
        self.tags = (try? c.decode([String].self, forKey: .tags)) ?? []
    }
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
    /// Wasm-only: maximum linear-memory growth in 64 KiB pages. The
    /// executor wires this into `Store.resourceLimiter`. Default 64 →
    /// 4 MiB total memory cap. Ignored for non-wasm kinds.
    public let maxWasmMemoryPages: Int
    /// Wasm-only: maximum table-element growth (function references,
    /// indirect calls). Default 1024. Ignored for non-wasm kinds.
    public let maxWasmTableElements: Int
    /// Wasm-only: best-effort cap on guest function-call count. Tracked
    /// via WasmKit's `EngineInterceptor`; the interceptor can't actually
    /// abort the wasm runtime (the protocol is observation-only), so the
    /// cap acts as a tripwire — once exceeded the outer timeout takes
    /// over and the call returns with `sandboxViolation`. A "real" gas
    /// counter would require a runtime that supports execution-time
    /// budgets; WasmKit doesn't ship one today.
    public let maxWasmFunctionCalls: Int

    public static let safeDefault = PluginSandboxPolicy(
        allowFilesystemRead: false, allowFilesystemWrite: false,
        allowNetwork: false, allowProcessSpawn: false,
        allowedRoots: [], maxOutputBytes: 64_000, timeoutSeconds: 30
    )

    public init(allowFilesystemRead: Bool, allowFilesystemWrite: Bool,
                allowNetwork: Bool, allowProcessSpawn: Bool,
                allowedRoots: [String], maxOutputBytes: Int, timeoutSeconds: Int,
                maxWasmMemoryPages: Int = 64,
                maxWasmTableElements: Int = 1024,
                maxWasmFunctionCalls: Int = 1_000_000) {
        self.allowFilesystemRead = allowFilesystemRead
        self.allowFilesystemWrite = allowFilesystemWrite
        self.allowNetwork = allowNetwork; self.allowProcessSpawn = allowProcessSpawn
        self.allowedRoots = allowedRoots; self.maxOutputBytes = maxOutputBytes
        self.timeoutSeconds = timeoutSeconds
        self.maxWasmMemoryPages = maxWasmMemoryPages
        self.maxWasmTableElements = maxWasmTableElements
        self.maxWasmFunctionCalls = maxWasmFunctionCalls
    }

    // Backward-compat decoding: manifests written before the wasm-limit
    // fields existed should still load with the safe defaults.
    private enum CodingKeys: String, CodingKey {
        case allowFilesystemRead, allowFilesystemWrite, allowNetwork, allowProcessSpawn
        case allowedRoots, maxOutputBytes, timeoutSeconds
        case maxWasmMemoryPages, maxWasmTableElements, maxWasmFunctionCalls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.allowFilesystemRead = (try? c.decode(Bool.self, forKey: .allowFilesystemRead)) ?? false
        self.allowFilesystemWrite = (try? c.decode(Bool.self, forKey: .allowFilesystemWrite)) ?? false
        self.allowNetwork = (try? c.decode(Bool.self, forKey: .allowNetwork)) ?? false
        self.allowProcessSpawn = (try? c.decode(Bool.self, forKey: .allowProcessSpawn)) ?? false
        self.allowedRoots = (try? c.decode([String].self, forKey: .allowedRoots)) ?? []
        self.maxOutputBytes = (try? c.decode(Int.self, forKey: .maxOutputBytes)) ?? 64_000
        self.timeoutSeconds = (try? c.decode(Int.self, forKey: .timeoutSeconds)) ?? 30
        self.maxWasmMemoryPages = (try? c.decode(Int.self, forKey: .maxWasmMemoryPages)) ?? 64
        self.maxWasmTableElements = (try? c.decode(Int.self, forKey: .maxWasmTableElements)) ?? 1024
        self.maxWasmFunctionCalls = (try? c.decode(Int.self, forKey: .maxWasmFunctionCalls)) ?? 1_000_000
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
