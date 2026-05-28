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

    /// Per-role provider overrides. When set, the specified provider gets a
    /// +2000 priority boost for that role — it always wins but fallback
    /// still works if it fails. Enables cloud/local mix-and-match.
    private var routeOverrides: [ModelRole: ProviderID] = [:]

    public init(registry: ProviderRegistry) {
        self.registry = registry
    }

    /// Set a per-role provider override for mix-and-match routing.
    /// Pass `nil` to clear the override and revert to default priority chain.
    public func setRouteOverride(role: ModelRole, providerID: ProviderID?) {
        if let providerID {
            routeOverrides[role] = providerID
            appendAudit(.init(kind: .routeSelected, providerID: providerID,
                              message: "Route override set: \(role.rawValue) → \(providerID)"))
        } else {
            routeOverrides.removeValue(forKey: role)
        }
    }

    /// Get the current route override for a role, if any.
    public func routeOverride(for role: ModelRole) -> ProviderID? {
        routeOverrides[role]
    }

    /// Get all current route overrides.
    public func allRouteOverrides() -> [ModelRole: ProviderID] {
        routeOverrides
    }

    /// Clear all route overrides.
    public func clearAllRouteOverrides() {
        routeOverrides.removeAll()
    }

    /// Complete a request using the best available route for the given role.
    /// Falls back through lower-priority routes on failure.
    public func complete(
        role: ModelRole, request: ModelRequest
    ) async throws -> ModelResponse {
        let candidates = await candidates(for: role, request: request)

        guard !candidates.isEmpty else {
            throw ProviderError.allRoutesFailed([])
        }

        var errors: [ProviderAttemptError] = []

        for route in candidates {
            guard let provider = await registry.provider(for: route.providerID) else {
                continue
            }

            do {
                let routedModel = model(for: request, route: route)
                let routed = request.withModel(routedModel)
                appendAudit(.init(kind: .callStarted, providerID: route.providerID,
                                  message: "Calling \(routedModel) via \(route.providerID)"))
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
        let candidates = await candidates(for: role, request: request)

        for route in candidates {
            guard let provider = await registry.provider(for: route.providerID),
                  let streamer = provider as? StreamingModelProviding else {
                continue
            }

            do {
                let routedModel = model(for: request, route: route)
                let routed = request.withModel(routedModel)
                appendAudit(.init(kind: .callStreamStarted, providerID: route.providerID,
                                  message: "Streaming \(routedModel) via \(route.providerID)"))
                return try await streamer.stream(routed)
            } catch {
                continue
            }
        }

        throw ProviderError.allRoutesFailed([])
    }

    public func embed(
        role: ModelRole = .embedding,
        request: EmbeddingRequest,
        providerID: ProviderID? = nil
    ) async throws -> EmbeddingResponse {
        let metadata = providerID.map { ["providerID": $0.rawValue] } ?? [:]
        let routingRequest = ModelRequest(
            model: request.model,
            messages: [],
            metadata: metadata
        )
        let candidates = await candidates(for: role, request: routingRequest)

        guard !candidates.isEmpty else {
            throw ProviderError.allRoutesFailed([])
        }

        var errors: [ProviderAttemptError] = []

        for route in candidates {
            guard let provider = await registry.provider(for: route.providerID) else {
                continue
            }
            guard let embedder = provider as? any EmbeddingProviding else {
                errors.append(ProviderAttemptError(
                    route: route,
                    error: ProviderError.unsupportedEndpoint(route.providerID, "embeddings")
                ))
                continue
            }

            do {
                let routedModel = model(for: request.model, route: route)
                let routed = EmbeddingRequest(model: routedModel, input: request.input)
                appendAudit(.init(kind: .callStarted, providerID: route.providerID,
                                  message: "Embedding \(routedModel) via \(route.providerID)"))
                let response = try await embedder.embed(routed)
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
            }
        }

        appendAudit(.init(kind: .allRoutesFailed, providerID: ProviderID("router"),
                          message: "All \(errors.count) routes failed for role \(role.rawValue)"))
        throw ProviderError.allRoutesFailed(errors)
    }

    private func candidates(for role: ModelRole, request: ModelRequest) async -> [ProviderRoute] {
        var routes = await registry.routes(for: role)

        // Apply per-role provider override as a priority boost
        if let overrideID = routeOverrides[role] {
            routes = routes.map { route in
                guard route.providerID == overrideID else { return route }
                return ProviderRoute(
                    id: route.id, role: route.role, providerID: route.providerID,
                    model: route.model, priority: route.priority + 2_000, enabled: route.enabled
                )
            }.sorted { $0.priority > $1.priority }
        }

        let scoped: [ProviderRoute]
        if let providerID = request.metadata["providerID"], !providerID.isEmpty {
            scoped = routes.filter { $0.providerID.rawValue == providerID }
        } else {
            scoped = routes
        }

        guard role == .embedding else { return scoped }
        var supported: [ProviderRoute] = []
        for route in scoped {
            guard let provider = await registry.provider(for: route.providerID),
                  provider.capabilities.embeddings else { continue }
            supported.append(route)
        }
        return supported
    }

    private nonisolated func model(for request: ModelRequest, route: ProviderRoute) -> String {
        model(for: request.model, route: route)
    }

    private nonisolated func model(for requestedModel: String, route: ProviderRoute) -> String {
        guard !requestedModel.isEmpty, requestedModel != "auto" else {
            return route.model
        }
        return requestedModel
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

        // Probe with a real model — the highest-priority enabled route for
        // this provider. An empty model name is rejected by most live APIs,
        // which would mis-report a healthy provider as `unreachable`.
        let probeModel = await registry.allRoutes()
            .filter { $0.providerID == id && $0.enabled }
            .sorted { $0.priority > $1.priority }
            .first?.model
        guard let probeModel else {
            return ProviderHealth(providerID: id, status: .unconfigured,
                                  message: "No route configured for provider \(id)")
        }

        let start = Date()
        do {
            let testReq = ModelRequest(
                model: probeModel, messages: [ChatMessage(role: .user, content: "Hello")],
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
