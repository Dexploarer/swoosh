// SwooshDaemon/PluginAPIBridge.swift — 0.8B Plugin host ↔ HTTP API
//
// One file. Translates `PluginHost` / `PluginRegistry` types into the
// wire-format payloads that `SwooshAPIServer` returns, and maps API
// errors into the right HTTPError kinds. Kept out of Daemon.swift so
// the long startup function stays readable.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshPlugins
import SwooshPluginRuntime
import SwooshTools

extension SwooshDaemon {
    static func pluginsResponse(host: PluginHost) async -> PluginsResponse {
        let manifests = await host.listAll()
        return PluginsResponse(plugins: manifests.map(pluginSummary))
    }

    static func pluginDetailResponse(
        host: PluginHost, registry: PluginRegistry, id: String
    ) async throws -> PluginDetailResponse {
        guard let manifest = await registry.getPlugin(id) else {
            throw APIError.notFound("plugin not found: \(id)")
        }
        let grants = await host.grantsFor(id)
        let auditEvents = await registry.getAuditLog(pluginID: id)
        let tail = auditEvents.suffix(50).map {
            PluginEventSummary(
                kind: $0.kind.rawValue,
                message: $0.message,
                createdAt: $0.createdAt
            )
        }
        return PluginDetailResponse(
            plugin: pluginSummary(manifest),
            grantedPermissions: grants.map(\.rawValue).sorted(),
            auditTail: tail
        )
    }

    static func enablePluginResponse(
        host: PluginHost, registry: PluginRegistry, id: String
    ) async throws -> PluginMutationResponse {
        do {
            try await host.enable(id)
        } catch let error as PluginError {
            throw mapPluginError(error)
        }
        guard let manifest = await registry.getPlugin(id) else {
            throw APIError.notFound("plugin disappeared after enable: \(id)")
        }
        return PluginMutationResponse(
            plugin: pluginSummary(manifest),
            message: "Plugin \(id) enabled."
        )
    }

    static func disablePluginResponse(
        host: PluginHost, registry: PluginRegistry, id: String
    ) async throws -> PluginMutationResponse {
        do {
            try await host.disable(id)
        } catch let error as PluginError {
            throw mapPluginError(error)
        }
        guard let manifest = await registry.getPlugin(id) else {
            throw APIError.notFound("plugin disappeared after disable: \(id)")
        }
        return PluginMutationResponse(
            plugin: pluginSummary(manifest),
            message: "Plugin \(id) disabled."
        )
    }

    static func installPluginResponse(
        host: PluginHost, request: PluginInstallRequest
    ) async throws -> PluginMutationResponse {
        let url = URL(fileURLWithPath: NSString(string: request.sourcePath).expandingTildeInPath, isDirectory: true)
        let manifest: PluginManifest
        do {
            manifest = try await host.installFromDirectory(url)
        } catch let error as PluginError {
            throw mapPluginError(error)
        } catch {
            throw APIError.badRequest("install failed: \(error.localizedDescription)")
        }
        return PluginMutationResponse(
            plugin: pluginSummary(manifest),
            message: "Plugin \(manifest.id) installed (disabled). Call enable to start it."
        )
    }

    static func uninstallPluginResponse(
        host: PluginHost, id: String
    ) async throws -> PluginsResponse {
        do {
            try await host.uninstall(id)
        } catch let error as PluginError {
            throw mapPluginError(error)
        }
        return await pluginsResponse(host: host)
    }

    // MARK: - Helpers

    static func pluginSummary(_ manifest: PluginManifest) -> PluginSummary {
        PluginSummary(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            kind: manifest.kind.rawValue,
            enabled: manifest.enabled,
            requestedPermissions: manifest.requestedPermissions,
            tools: manifest.tools.map {
                PluginToolSummary(
                    name: $0.name, description: $0.description,
                    permission: $0.permission.rawValue,
                    risk: $0.risk.rawValue,
                    requiresApproval: $0.requiresApproval
                )
            },
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt
        )
    }

    private static func mapPluginError(_ error: PluginError) -> APIError {
        switch error {
        case .notFound(let id):
            return .notFound("plugin not found: \(id)")
        case .alreadyExists(let id):
            return .badRequest("plugin already exists: \(id)")
        case .notEnabled(let id):
            return .badRequest("plugin not enabled: \(id)")
        case .sandboxViolation(let msg):
            return .badRequest("sandbox violation: \(msg)")
        case .toolFailed(let msg):
            return .badRequest("plugin tool failed: \(msg)")
        case .toolNotRegistered(let name):
            return .notFound("plugin tool not registered: \(name)")
        case .approvalRequired(let id):
            return .badRequest("approval required for plugin: \(id)")
        case .validationFailed(let id, let errs):
            let joined = errs.map(\.description).joined(separator: "; ")
            return .badRequest("manifest \(id) failed validation: \(joined)")
        case .missingEntrypoint(let id, let detail):
            return .badRequest("plugin \(id) entrypoint unavailable: \(detail)")
        }
    }
}
