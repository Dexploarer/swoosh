// Tests/SwooshAPITests/PluginRoutesTests.swift — 0.8B
//
// Wire-level coverage for the /api/plugins/* routes. The runtime
// callbacks return canned responses; the assertions verify that the
// router actually hooks them up and serializes their output correctly
// over HTTP.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

private func makeSummary(
    id: String, kind: String = "swift", enabled: Bool = false
) -> PluginSummary {
    PluginSummary(
        id: id, name: id, version: "1.0.0",
        description: nil, author: nil, kind: kind, enabled: enabled,
        requestedPermissions: ["toolRead"],
        tools: [PluginToolSummary(
            name: "echo", description: "",
            permission: "toolRead", risk: "readOnly", requiresApproval: false
        )],
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

@Suite("Plugin routes")
struct PluginRoutesTests {

    @Test("GET /api/plugins returns the runtime-source list")
    func listPlugins() async throws {
        let sources = SwooshAPIRuntimeSources(
            plugins: {
                PluginsResponse(plugins: [makeSummary(id: "a"), makeSummary(id: "b", enabled: true)])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/plugins", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try testDecoder().decode(PluginsResponse.self, from: Data(buffer: response.body))
                #expect(body.plugins.map(\.id) == ["a", "b"])
                #expect(body.plugins.first { $0.id == "b" }?.enabled == true)
            }
        }
    }

    @Test("POST /api/plugins/:id/enable invokes runtime source")
    func enablePlugin() async throws {
        let calls = ResultBox<String>()
        let sources = SwooshAPIRuntimeSources(
            enablePlugin: { id in
                await calls.set(id)
                return PluginMutationResponse(
                    plugin: makeSummary(id: id, enabled: true),
                    message: "ok"
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/plugins/demo/enable", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try testDecoder().decode(PluginMutationResponse.self, from: Data(buffer: response.body))
                #expect(body.plugin.enabled)
            }
        }
        #expect(await calls.value == "demo")
    }

    @Test("DELETE /api/plugins/:id maps to uninstall")
    func uninstallPlugin() async throws {
        let calls = ResultBox<String>()
        let sources = SwooshAPIRuntimeSources(
            uninstallPlugin: { id in
                await calls.set(id)
                return PluginsResponse(plugins: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/plugins/demo", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try testDecoder().decode(PluginsResponse.self, from: Data(buffer: response.body))
                #expect(body.plugins.isEmpty)
            }
        }
        #expect(await calls.value == "demo")
    }

    @Test("install route round-trips the source path")
    func installPlugin() async throws {
        let calls = ResultBox<String>()
        let sources = SwooshAPIRuntimeSources(
            installPlugin: { request in
                await calls.set(request.sourcePath)
                return PluginMutationResponse(
                    plugin: makeSummary(id: "from-disk"),
                    message: "installed"
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(PluginInstallRequest(sourcePath: "/tmp/source"))
            try await client.execute(
                uri: "/api/plugins/install", method: .post,
                headers: [
                    .authorization: "Bearer secret",
                    .contentType: "application/json",
                ],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try testDecoder().decode(PluginMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.plugin.id == "from-disk")
            }
        }
        #expect(await calls.value == "/tmp/source")
    }

    @Test("GET /api/plugins/:id returns detail with audit tail")
    func pluginDetail() async throws {
        let sources = SwooshAPIRuntimeSources(
            pluginDetail: { id in
                PluginDetailResponse(
                    plugin: makeSummary(id: id, enabled: true),
                    grantedPermissions: ["toolRead"],
                    auditTail: [
                        PluginEventSummary(
                            kind: "enabled",
                            message: "plugin enabled",
                            createdAt: Date(timeIntervalSince1970: 1234)
                        ),
                    ]
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/plugins/demo", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try testDecoder().decode(PluginDetailResponse.self, from: Data(buffer: response.body))
                #expect(body.plugin.id == "demo")
                #expect(body.grantedPermissions == ["toolRead"])
                #expect(body.auditTail.first?.kind == "enabled")
            }
        }
    }

    @Test("unauthenticated request to /api/plugins returns 401")
    func authRequired() async throws {
        let app = SwooshAPIServer(token: "secret").build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/plugins", method: .get
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }
}

/// Tiny actor for capturing a value from inside a `@Sendable` closure.
private actor ResultBox<T: Sendable> {
    private var stored: T?
    func set(_ value: T) { stored = value }
    var value: T? { stored }
}

/// Server encodes dates as ISO8601 strings (matches Hummingbird default).
/// Pair the test decoder with the same strategy.
private func testDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
