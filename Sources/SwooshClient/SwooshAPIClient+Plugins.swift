// SwooshClient/SwooshAPIClient+Plugins.swift — 0.4A Plugin endpoint methods
//
// Split from SwooshAPIClient.swift to honour the 400-LOC ceiling.
// Covers `GET /api/plugins`, `GET /api/plugins/{id}`, and the
// install/enable/disable/uninstall mutations.

import Foundation

extension SwooshAPIClient {
    public func plugins() async throws -> PluginsResponse {
        let request = try makeRequest(method: "GET", path: "api/plugins", body: nil)
        return try await execute(request, as: PluginsResponse.self)
    }

    public func plugin(id: String) async throws -> PluginDetailResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/plugins/\(encodedID)", body: nil)
        return try await execute(request, as: PluginDetailResponse.self)
    }

    public func enablePlugin(id: String) async throws -> PluginMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/plugins/\(encodedID)/enable", body: nil)
        return try await execute(request, as: PluginMutationResponse.self)
    }

    public func disablePlugin(id: String) async throws -> PluginMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/plugins/\(encodedID)/disable", body: nil)
        return try await execute(request, as: PluginMutationResponse.self)
    }

    public func installPlugin(sourcePath: String) async throws -> PluginMutationResponse {
        let body = try encoder.encode(PluginInstallRequest(sourcePath: sourcePath))
        let request = try makeRequest(method: "POST", path: "api/plugins/install", body: body)
        return try await execute(request, as: PluginMutationResponse.self)
    }

    public func uninstallPlugin(id: String) async throws -> PluginsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/plugins/\(encodedID)", body: nil)
        return try await execute(request, as: PluginsResponse.self)
    }
}
