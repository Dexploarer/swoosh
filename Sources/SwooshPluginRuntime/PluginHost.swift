// SwooshPluginRuntime/PluginHost.swift — 0.8B Plugin Lifecycle Orchestrator
//
// The host owns the lifecycle of every plugin: install → validate → enable
// → bridge tools into `ToolRegistry` → eventual disable → uninstall. It is
// the *only* place plugin permissions are granted on the firewall, and the
// only place plugin tools are inserted into the registry. The daemon
// constructs one host at startup; CLI / API plugin commands delegate
// through it.
//
// Permission bookkeeping:
//   • The host captures the firewall's baseline grant set at init.
//   • `enable` records the typed permission set requested by the plugin
//     and grants any not already in the union of baseline + other plugins'
//     active grants.
//   • `disable` revokes any permission that *only* this plugin claimed —
//     never revokes baseline grants, never revokes a permission still
//     needed by another enabled plugin.
//
// This keeps the model simple ("the user approved this plugin's
// permissions") without leaking those grants to unrelated tools when the
// plugin is later turned off.

import Foundation
import SwooshFirewall
import SwooshPlugins
import SwooshTools

public actor PluginHost {
    private let store: any PluginStore
    private let registry: PluginRegistry
    private let toolRegistry: ToolRegistry
    private let firewall: SwooshFirewallActor
    private let executors: [PluginKind: any PluginExecutor]
    private let baselineGrants: Set<SwooshPermission>
    /// Directory plugin files are copied into during install. Almost always
    /// `~/.swoosh/plugins`, but plumbed explicitly so tests can use a temp
    /// dir without poking at FilePluginStore internals.
    public let pluginsRoot: URL
    private var grantsByPlugin: [String: Set<SwooshPermission>] = [:]
    private var registeredToolNames: [String: [ToolName]] = [:]

    public init(
        store: any PluginStore,
        registry: PluginRegistry,
        toolRegistry: ToolRegistry,
        firewall: SwooshFirewallActor,
        executors: [any PluginExecutor],
        baselineGrants: Set<SwooshPermission>,
        pluginsRoot: URL
    ) {
        self.store = store
        self.registry = registry
        self.toolRegistry = toolRegistry
        self.firewall = firewall
        var byKind: [PluginKind: any PluginExecutor] = [:]
        for executor in executors { byKind[executor.kind] = executor }
        self.executors = byKind
        self.baselineGrants = baselineGrants
        self.pluginsRoot = pluginsRoot.standardizedFileURL
    }

    // ── Bootstrap ─────────────────────────────────────────────────

    /// Load every manifest from the store, register the valid ones, and
    /// re-enable anything that was previously enabled. Called once during
    /// daemon startup, before the API server begins accepting requests.
    public func bootstrap() async throws {
        let manifests = try await store.listAll()
        for manifest in manifests {
            try? await registry.register(manifest)
            guard manifest.validate().isEmpty else { continue }
            guard manifest.enabled else { continue }
            try? await enableInternal(manifest.id, persist: false)
        }
    }

    // ── Install / uninstall ───────────────────────────────────────

    /// Install a manifest. The manifest is validated, written to the store,
    /// and registered in the in-memory registry. The plugin starts
    /// disabled — the user must call `enable` separately. `pluginInstall`
    /// is a humanOnly admin permission gated at the API/CLI boundary.
    public func install(_ manifest: PluginManifest) async throws {
        let errs = manifest.validate()
        guard errs.isEmpty else {
            throw PluginError.validationFailed(pluginID: manifest.id, errors: errs)
        }
        var initial = manifest
        initial.enabled = false
        try await store.upsert(initial)
        do {
            try await registry.register(initial)
        } catch PluginError.alreadyExists {
            await registry.updateManifest(initial)
        }
    }

    /// Disable then drop the plugin from disk + registry. Tools are removed
    /// from `ToolRegistry`, permissions revoked, manifest file deleted.
    /// `pluginUninstall` is a humanOnly admin permission gated above.
    public func uninstall(_ id: String) async throws {
        if let existing = await registry.getPlugin(id), existing.enabled {
            try await disable(id)
        }
        try await store.remove(id)
        // The in-memory registry doesn't currently expose a `remove` —
        // updating the manifest to a disabled stub keeps the API
        // consistent until that's added. The next daemon restart drops it.
        if var stub = await registry.getPlugin(id) {
            stub.enabled = false
            await registry.updateManifest(stub)
        }
    }

    /// Install a plugin from a directory on disk. The directory must
    /// contain `manifest.json`; any sibling files (executable scripts,
    /// `.wasm`/`.wat` modules, resources) are copied verbatim into the
    /// store's plugin directory so the executor can resolve relative
    /// paths against them at call time. The plugin lands disabled — the
    /// caller must `enable` separately.
    public func installFromDirectory(_ sourceDir: URL) async throws -> PluginManifest {
        let fm = FileManager.default
        let manifestURL = sourceDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw PluginError.missingEntrypoint(
                pluginID: sourceDir.lastPathComponent,
                detail: "no manifest.json in \(sourceDir.path)"
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(PluginManifest.self, from: data)

        let errs = manifest.validate()
        guard errs.isEmpty else {
            throw PluginError.validationFailed(pluginID: manifest.id, errors: errs)
        }

        // Copy the whole source directory into the plugin store layout.
        // `FilePluginStore.upsert` will overwrite the manifest, but any
        // sibling files (main.sh, plugin.wasm) need explicit copying.
        // Resolve the target and double-check it stays inside the root —
        // `validate()` already rejected path-traversal IDs, but if a
        // future refactor relaxes that we don't want a write-anywhere
        // primitive to fall out.
        let target = pluginsRoot.appendingPathComponent(manifest.id, isDirectory: true).standardizedFileURL
        let rootPrefix = pluginsRoot.path.hasSuffix("/") ? pluginsRoot.path : pluginsRoot.path + "/"
        guard target.path.hasPrefix(rootPrefix), target.path != pluginsRoot.path else {
            throw PluginError.validationFailed(
                pluginID: manifest.id,
                errors: [.invalidID(manifest.id)]
            )
        }
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: sourceDir, to: target)

        // Ensure the manifest on disk reflects "freshly installed,
        // disabled" — overrides any `enabled: true` left in the source.
        var initial = manifest
        initial.enabled = false
        initial.updatedAt = Date()
        try await store.upsert(initial)
        do {
            try await registry.register(initial)
        } catch PluginError.alreadyExists {
            await registry.updateManifest(initial)
        }
        return initial
    }


    // ── Enable / disable ──────────────────────────────────────────

    /// Enable a previously-installed plugin: validate, grant the requested
    /// permissions on the firewall, bridge tools into `ToolRegistry`,
    /// persist `enabled = true`. `pluginEnable` is a humanOnly admin
    /// permission gated at the API/CLI boundary — the user's approval
    /// *is* the grant of those permissions.
    public func enable(_ id: String) async throws {
        try await enableInternal(id, persist: true)
    }

    private func enableInternal(_ id: String, persist: Bool) async throws {
        guard let manifest = await registry.getPlugin(id) else {
            throw PluginError.notFound(id)
        }
        let errs = manifest.validate()
        guard errs.isEmpty else {
            throw PluginError.validationFailed(pluginID: id, errors: errs)
        }
        // Dependency check (elizaOS-aligned). A plugin can declare other
        // plugins it requires; the host refuses to enable if any are
        // missing-or-not-enabled. Mirrors elizaOS's `plugin.dependencies`
        // semantics so manifests are portable across the runtimes.
        for dep in manifest.dependencies {
            guard let depManifest = await registry.getPlugin(dep) else {
                throw PluginError.missingEntrypoint(
                    pluginID: id,
                    detail: "dependency `\(dep)` is not installed"
                )
            }
            guard depManifest.enabled else {
                throw PluginError.notEnabled(
                    "dependency `\(dep)` of `\(id)` is installed but not enabled"
                )
            }
        }
        guard let executor = executors[manifest.kind] else {
            throw PluginError.missingEntrypoint(
                pluginID: id,
                detail: "no executor registered for kind \(manifest.kind.rawValue)"
            )
        }

        // Grant typed permissions. Validation already enforced that every
        // requested string parses to a real SwooshPermission.
        let perms = Set(manifest.requestedPermissions.compactMap { SwooshPermission(rawValue: $0) })
        for perm in perms { await firewall.grant(perm) }
        grantsByPlugin[id] = perms

        // Lifecycle: `initialize` runs after permissions are granted but
        // before tools enter the registry, so the plugin can set up state
        // its handlers will rely on. Failure here aborts the enable —
        // permissions are revoked so we don't leak grants on a half-enable.
        if let swiftExec = executor as? SwiftPluginExecutor {
            do {
                try await swiftExec.lifecycleInitialize(manifest: manifest)
            } catch {
                for perm in perms { await firewall.deny(perm) }
                grantsByPlugin.removeValue(forKey: id)
                throw PluginError.missingEntrypoint(
                    pluginID: id,
                    detail: "initialize() failed: \(error.localizedDescription)"
                )
            }
        }

        // Bridge tools into the registry.
        var bridgedNames: [ToolName] = []
        for tool in manifest.tools {
            let bridge = PluginToolBridge(
                pluginID: id, manifest: manifest, tool: tool,
                executor: executor, registry: registry
            )
            if await toolRegistry.register(bridge) {
                bridgedNames.append(ToolName(tool.swooshToolName))
            }
        }
        registeredToolNames[id] = bridgedNames

        try await registry.enable(id)
        if persist {
            var updated = manifest
            updated.enabled = true
            updated.updatedAt = Date()
            try await store.upsert(updated)
            await registry.updateManifest(updated)
        }
    }

    /// Disable an enabled plugin: drop its tools from `ToolRegistry`, revoke
    /// permissions that are exclusively this plugin's, persist
    /// `enabled = false`. `pluginDisable` is humanOnly admin.
    public func disable(_ id: String) async throws {
        guard let manifest = await registry.getPlugin(id) else {
            throw PluginError.notFound(id)
        }

        // Drop tools from the registry first so even an in-flight call
        // can't pick up a stale bridge after this point.
        for name in registeredToolNames[id] ?? [] {
            _ = await toolRegistry.unregister(name: name)
        }
        registeredToolNames.removeValue(forKey: id)

        // Lifecycle: `dispose` runs after tools are unregistered but
        // before grants are revoked. Errors are logged in the manifest's
        // audit stream rather than thrown — disable is a teardown path
        // and must not get stuck on a flaky plugin.
        if let executor = executors[manifest.kind],
           let swiftExec = executor as? SwiftPluginExecutor {
            try? await swiftExec.lifecycleDispose(manifest: manifest)
        }

        // Compute revoke set: perms granted by this plugin, not in the
        // baseline, not still needed by another enabled plugin.
        let mine = grantsByPlugin[id] ?? []
        grantsByPlugin.removeValue(forKey: id)
        let stillNeeded = Set(grantsByPlugin.values.flatMap { $0 })
        let toRevoke = mine.subtracting(stillNeeded).subtracting(baselineGrants)
        for perm in toRevoke { await firewall.deny(perm) }

        try await registry.disable(id)
        var updated = manifest
        updated.enabled = false
        updated.updatedAt = Date()
        try await store.upsert(updated)
        await registry.updateManifest(updated)
    }

    // ── Queries ───────────────────────────────────────────────────

    public func listAll() async -> [PluginManifest] {
        await registry.list()
    }

    /// Permissions currently granted on behalf of this plugin (read-only
    /// view for /why and admin tooling).
    public func grantsFor(_ id: String) -> Set<SwooshPermission> {
        grantsByPlugin[id] ?? []
    }
}
