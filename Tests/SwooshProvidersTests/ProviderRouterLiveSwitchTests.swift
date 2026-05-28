// Tests/SwooshProvidersTests/ProviderRouterLiveSwitchTests.swift — 0.1A
//
// Integration: prove the live provider switch end-to-end. Two stub
// providers are registered for the same role; the router routes to the
// higher-priority one by default, `setRouteOverride` flips every call to
// the chosen provider with no rebuild, and clearing the override restores
// priority routing. This is the mechanism behind `POST /api/providers/select`
// and `swoosh provider select` (config-driven registry, live switching).

import Testing
import Foundation
@testable import SwooshProviders
@testable import SwooshTools

/// Returns `from-<id>` so the test can assert which provider actually served.
private struct StubModelProvider: ModelProviding {
    let providerID: ProviderID
    let displayName: String
    let capabilities = ProviderCapabilities(
        streaming: false, toolCalling: false, structuredOutput: false,
        embeddings: false, vision: false
    )
    init(_ id: String) { self.providerID = ProviderID(id); self.displayName = id }
    func complete(_ request: ModelRequest) async throws -> ModelResponse {
        ModelResponse(providerID: providerID, model: request.model, text: "from-\(providerID.rawValue)")
    }
}

@Suite("ProviderRouter live switch")
struct ProviderRouterLiveSwitchTests {

    private func router() async -> ProviderRouter {
        let registry = ProviderRegistry()
        await registry.register(StubModelProvider("alpha"), profile: ProviderProfile(
            id: ProviderID("alpha"), kind: .openAI, displayName: "Alpha", enabled: true))
        await registry.register(StubModelProvider("beta"), profile: ProviderProfile(
            id: ProviderID("beta"), kind: .openAI, displayName: "Beta", enabled: true))
        // alpha outranks beta by route priority.
        await registry.addRoute(ProviderRoute(role: .primaryChat, providerID: "alpha", model: "m", priority: 100))
        await registry.addRoute(ProviderRoute(role: .primaryChat, providerID: "beta", model: "m", priority: 90))
        return ProviderRouter(registry: registry)
    }

    private let req = ModelRequest(model: "auto", messages: [ChatMessage(role: .user, content: "hi")])

    @Test("Default routing picks the highest-priority provider")
    func defaultRouting() async throws {
        let resp = try await router().complete(role: .primaryChat, request: req)
        #expect(resp.text == "from-alpha")
        #expect(resp.providerID == ProviderID("alpha"))
    }

    @Test("setRouteOverride flips the served provider with no rebuild")
    func overrideFlips() async throws {
        let router = await router()
        #expect(try await router.complete(role: .primaryChat, request: req).text == "from-alpha")

        await router.setRouteOverride(role: .primaryChat, providerID: ProviderID("beta"))
        #expect(await router.routeOverride(for: .primaryChat) == ProviderID("beta"))
        #expect(try await router.complete(role: .primaryChat, request: req).text == "from-beta")
    }

    @Test("Clearing the override restores priority routing")
    func clearRestores() async throws {
        let router = await router()
        await router.setRouteOverride(role: .primaryChat, providerID: ProviderID("beta"))
        #expect(try await router.complete(role: .primaryChat, request: req).text == "from-beta")

        await router.setRouteOverride(role: .primaryChat, providerID: nil)
        #expect(await router.routeOverride(for: .primaryChat) == nil)
        #expect(try await router.complete(role: .primaryChat, request: req).text == "from-alpha")
    }

    @Test("Override is per-role — other roles keep their own routing")
    func overrideIsPerRole() async throws {
        let router = await router()
        await router.setRouteOverride(role: .coding, providerID: ProviderID("beta"))
        // primaryChat has no override, so it still routes by priority.
        #expect(try await router.complete(role: .primaryChat, request: req).text == "from-alpha")
    }
}
