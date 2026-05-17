// SwooshProviders/ProviderRouter.swift — 0.9P Provider Registry + Fallback Router
//
// Role-based routing with fallback. Audited. Never exposes secrets.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider registry
// ═══════════════════════════════════════════════════════════════════

public actor ProviderRegistry {
    private var providers: [ProviderID: any ModelProviding] = [:]
    private var profiles: [ProviderID: ProviderProfile] = [:]
    private var routes: [ProviderRoute] = []
    private var healthCache: [ProviderID: ProviderHealth] = [:]

    public init() {}

    // ── Registration ──────────────────────────────────────────────

    public func register(_ provider: any ModelProviding, profile: ProviderProfile) {
        providers[provider.providerID] = provider
        profiles[provider.providerID] = profile
    }

    public func provider(for id: ProviderID) -> (any ModelProviding)? {
        providers[id]
    }

    public func profile(for id: ProviderID) -> ProviderProfile? {
        profiles[id]
    }

    public func allProfiles() -> [ProviderProfile] {
        Array(profiles.values).sorted { $0.priority > $1.priority }
    }

    public func allProviderIDs() -> [ProviderID] {
        Array(providers.keys)
    }

    // ── Routes ────────────────────────────────────────────────────

    public func addRoute(_ route: ProviderRoute) {
        routes.append(route)
    }

    public func setRoutes(_ newRoutes: [ProviderRoute]) {
        routes = newRoutes
    }

    public func routes(for role: ModelRole) -> [ProviderRoute] {
        routes
            .filter { $0.role == role && $0.enabled }
            .sorted { $0.priority > $1.priority }
    }

    public func allRoutes() -> [ProviderRoute] { routes }

    // ── Health ─────────────────────────────────────────────────────

    public func updateHealth(_ health: ProviderHealth) {
        healthCache[health.providerID] = health
    }

    public func health(for id: ProviderID) -> ProviderHealth? {
        healthCache[id]
    }

    // ── Enable/Disable ────────────────────────────────────────────

    public func enable(_ id: ProviderID) {
        profiles[id]?.enabled = true
    }

    public func disable(_ id: ProviderID) {
        profiles[id]?.enabled = false
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider router
// ═══════════════════════════════════════════════════════════════════

public actor ProviderRouter {
    private let registry: ProviderRegistry
    private var auditLog: [ProviderAuditEvent] = []

    public init(registry: ProviderRegistry) {
        self.registry = registry
    }

    /// Complete a request using the best available route for the given role.
    /// Falls back through lower-priority routes on failure.
    public func complete(
        role: ModelRole, request: ModelRequest
    ) async throws -> ModelResponse {
        let candidates = await registry.routes(for: role)

        guard !candidates.isEmpty else {
            throw ProviderError.allRoutesFailed([])
        }

        var errors: [ProviderAttemptError] = []

        for route in candidates {
            guard let provider = await registry.provider(for: route.providerID) else {
                continue
            }

            do {
                let routed = request.withModel(route.model)
                appendAudit(.init(kind: .callStarted, providerID: route.providerID,
                                  message: "Calling \(route.model) via \(route.providerID)"))
                let response = try await provider.complete(routed)
                appendAudit(.init(kind: .callSucceeded, providerID: route.providerID,
                                  message: "Success: \(response.usage?.totalTokens ?? 0) tokens"))
                appendAudit(.init(kind: .routeSelected, providerID: route.providerID,
                                  message: "Route \(route.id) for role \(role.rawValue)"))
                return response
            } catch {
                let attempt = ProviderAttemptError(route: route, error: error)
                errors.append(attempt)
                appendAudit(.init(kind: .callFailed, providerID: route.providerID,
                                  message: "Failed: \(error.localizedDescription)"))
                if errors.count > 1 {
                    appendAudit(.init(kind: .routeFallback, providerID: route.providerID,
                                      message: "Falling back from \(route.providerID)"))
                }
            }
        }

        appendAudit(.init(kind: .allRoutesFailed, providerID: ProviderID("router"),
                          message: "All \(errors.count) routes failed for role \(role.rawValue)"))
        throw ProviderError.allRoutesFailed(errors)
    }

    /// Stream a request using the best available streaming route.
    public func stream(
        role: ModelRole, request: ModelRequest
    ) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        let candidates = await registry.routes(for: role)

        for route in candidates {
            guard let provider = await registry.provider(for: route.providerID),
                  let streamer = provider as? StreamingModelProviding else {
                continue
            }

            do {
                let routed = request.withModel(route.model)
                appendAudit(.init(kind: .callStreamStarted, providerID: route.providerID,
                                  message: "Streaming \(route.model) via \(route.providerID)"))
                return try await streamer.stream(routed)
            } catch {
                continue
            }
        }

        throw ProviderError.allRoutesFailed([])
    }

    /// Complete a request using a specific provider directly (bypass routing).
    /// Used by test/diagnostic commands.
    public func completeWith(
        providerID: ProviderID, request: ModelRequest
    ) async throws -> ModelResponse {
        guard let provider = await registry.provider(for: providerID) else {
            throw ProviderError.notConfigured(providerID)
        }
        return try await provider.complete(request)
    }

    // ── Health check ──────────────────────────────────────────────

    public func testProvider(_ id: ProviderID) async -> ProviderHealth {
        guard let provider = await registry.provider(for: id) else {
            return ProviderHealth(providerID: id, status: .unconfigured, message: "Provider not registered")
        }

        let start = Date()
        do {
            let testReq = ModelRequest(
                model: "", messages: [ChatMessage(role: .user, content: "Hello")],
                maxOutputTokens: 10
            )
            _ = try await provider.complete(testReq)
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            let health = ProviderHealth(providerID: id, status: .healthy, latencyMs: latency)
            await registry.updateHealth(health)
            appendAudit(.init(kind: .testSucceeded, providerID: id,
                              message: "Health test passed in \(latency)ms"))
            return health
        } catch {
            let health = ProviderHealth(providerID: id, status: .unreachable,
                                        message: error.localizedDescription)
            await registry.updateHealth(health)
            appendAudit(.init(kind: .testFailed, providerID: id,
                              message: "Health test failed: \(error.localizedDescription)"))
            return health
        }
    }

    // ── Audit ─────────────────────────────────────────────────────

    private func appendAudit(_ event: ProviderAuditEvent) { auditLog.append(event) }
    public func getAuditLog() -> [ProviderAuditEvent] { auditLog }
}
