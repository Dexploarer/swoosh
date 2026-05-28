// Tests/SwooshProvidersTests/ProviderConfigRouterTests.swift — 0.1A
//
// Config-driven provider registry + live switching:
//   • ProviderConfig Codable round-trip + validation filtering
//   • ProviderConfigStore load/save/absent/setActiveProvider
//   • makeProvider(kind:) → correct concrete provider per kind
//   • buildRouter(config:) registers a config provider and the active
//     selection wins its text-role route (the priority boost)
//   • router.setRouteOverride flips the active provider live
// No network — routing is asserted via the registry's route table.

import Testing
import Foundation
@testable import SwooshModels
@testable import SwooshProviders
@testable import SwooshProviderBridge
@testable import SwooshSecrets
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - ProviderConfig model + store
// ═══════════════════════════════════════════════════════════════════

@Suite("ProviderConfig model")
struct ProviderConfigModelTests {

    @Test("Decodes a providers.json document")
    func decode() throws {
        let json = """
        {
          "activeProviderID": "my-proxy",
          "providers": [
            { "id": "my-proxy", "kind": "localOpenAICompatible",
              "displayName": "My Proxy", "baseURL": "http://localhost:3001/v1",
              "secretRef": "my-proxy.api_key", "enabled": true,
              "models": { "primaryChat": "auto" } }
          ],
          "routeOverrides": [
            { "role": "coding", "providerID": "my-proxy", "model": "qwen", "priority": 70 }
          ]
        }
        """
        let config = try JSONDecoder().decode(ProviderConfig.self, from: Data(json.utf8))
        #expect(config.activeProviderID == "my-proxy")
        #expect(config.providers.count == 1)
        #expect(config.providers.first?.models?["primaryChat"] == "auto")
        #expect(config.routeOverrides.first?.role == "coding")
    }

    @Test("enabledValidProviders filters disabled + structurally invalid")
    func filtering() {
        let config = ProviderConfig(providers: [
            ProviderConfigEntry(id: "good", kind: "openAI", displayName: "Good", enabled: true),
            ProviderConfigEntry(id: "off", kind: "openAI", displayName: "Off", enabled: false),
            ProviderConfigEntry(id: "", kind: "openAI", displayName: "Blank id", enabled: true),
        ])
        let valid = config.enabledValidProviders
        #expect(valid.count == 1)
        #expect(valid.first?.id == "good")
    }

    @Test("Store: absent → empty; save/load round-trip; setActiveProvider")
    func store() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ProviderConfigStore(directory: dir)
        #expect(store.load() == .empty) // absent file

        var config = ProviderConfig(providers: [
            ProviderConfigEntry(id: "p1", kind: "anthropic", displayName: "P1", enabled: true),
        ])
        try store.save(config)
        #expect(store.load().providers.first?.id == "p1")

        config = try store.setActiveProvider("p1")
        #expect(config.activeProviderID == "p1")
        #expect(store.load().activeProviderID == "p1")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - makeProvider(kind:)
// ═══════════════════════════════════════════════════════════════════

@Suite("makeProvider(kind:)")
struct MakeProviderTests {

    private func make(_ kind: ProviderKind, id: String = "x") -> (any ModelProviding)? {
        ProviderFactory.makeProvider(
            kind: kind, baseURL: nil, apiKey: nil,
            providerID: ProviderID(id), displayName: "X", secrets: InMemorySecretStore()
        )
    }

    @Test("Cloud kinds construct with their canonical ids")
    func cloudKinds() {
        #expect(make(.openAI)?.providerID == ProviderID("openai"))
        #expect(make(.anthropic)?.providerID == ProviderID("anthropic"))
        #expect(make(.openRouter)?.providerID == ProviderID("openrouter"))
        #expect(make(.detourCloud)?.providerID == ProviderID("detour-cloud"))
        #expect(make(.codexCLI)?.providerID == ProviderID("codex"))
    }

    @Test("localOpenAICompatible adopts the config-provided id")
    func localAdoptsID() {
        #expect(make(.localOpenAICompatible, id: "my-proxy")?.providerID == ProviderID("my-proxy"))
    }

    @Test("mlx is not constructible from config")
    func mlxNil() {
        #expect(make(.mlx) == nil)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - buildRouter(config:) + live override
// ═══════════════════════════════════════════════════════════════════

@Suite("buildRouter with config")
struct BuildRouterConfigTests {

    @Test("Config provider is registered and the active selection wins its route")
    func activeWins() async {
        let config = ProviderConfig(
            activeProviderID: "my-proxy",
            providers: [
                ProviderConfigEntry(
                    id: "my-proxy", kind: "localOpenAICompatible", displayName: "My Proxy",
                    baseURL: "http://localhost:3001/v1", secretRef: "my-proxy.api_key",
                    defaultModel: "auto", enabled: true,
                    models: ["primaryChat": "auto"]
                )
            ]
        )
        let (_, registry) = await ProviderFactory.buildRouter(
            secrets: InMemorySecretStore(), config: config
        )
        // Provider registered.
        let ids = await registry.allProviderIDs().map(\.rawValue)
        #expect(ids.contains("my-proxy"))
        // Active provider's primaryChat route outranks the built-ins.
        let routes = await registry.routes(for: .primaryChat)
        #expect(routes.first?.providerID == ProviderID("my-proxy"))
    }

    @Test("Empty config leaves built-in providers intact")
    func emptyConfigUnchanged() async {
        let (_, registry) = await ProviderFactory.buildRouter(
            secrets: InMemorySecretStore(), config: .empty
        )
        let ids = await registry.allProviderIDs().map(\.rawValue)
        #expect(ids.contains("openai"))
        #expect(ids.contains("anthropic"))
        #expect(ids.contains("dev-proxy"))
    }

    @Test("Live setRouteOverride records the chosen provider per role")
    func liveOverride() async {
        let registry = ProviderRegistry()
        let router = ProviderRouter(registry: registry)
        for role in ProviderFactory.textRoles {
            await router.setRouteOverride(role: role, providerID: ProviderID("dev-proxy"))
        }
        let primary = await router.routeOverride(for: .primaryChat)
        let coding = await router.routeOverride(for: .coding)
        #expect(primary == ProviderID("dev-proxy"))
        #expect(coding == ProviderID("dev-proxy"))
    }
}
