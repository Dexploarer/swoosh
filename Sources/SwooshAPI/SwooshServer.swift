// SwooshAPI/SwooshServer.swift — HTTP API server
//
// Hummingbird router with three layers:
//
//   1. Public routes  — `/health`, `/api/version`. No auth, safe to expose.
//   2. Auth-gated     — every other `/api/*` route. Requires a bearer token.
//                       When the daemon was started without one, the entire
//                       `/api/*` tree is shadow-mounted under DenyAllMiddleware
//                       so binding to 0.0.0.0 still can't expose the agent.
//   3. Agent          — `POST /api/agent/chat` calls `AgentKernel.run()` and
//                       returns a `ChatResponse` JSON body.
//
// Streaming / WebSocket and the audit/approvals endpoints will land on top of
// this once the iOS slice is proven; this file is intentionally the smallest
// thing that gives the phone a real conversation.

import Foundation
import Hummingbird
import SwooshCore
import SwooshClient
import SwooshChatSDK

// Server-side conformance so `ChatResponse` can be returned from a Hummingbird
// route directly. `SwooshClient` itself doesn't import Hummingbird.
extension ChatResponse: ResponseEncodable {}
extension APIErrorBody: ResponseEncodable {}
extension APIVersion: ResponseEncodable {}
extension AgentStatusResponse: ResponseEncodable {}
extension ProvidersResponse: ResponseEncodable {}
extension ProviderStatusResponse: ResponseEncodable {}
extension BoardCardsResponse: ResponseEncodable {}
extension BoardLanesResponse: ResponseEncodable {}
extension MetricsResponse: ResponseEncodable {}
extension UsageResponse: ResponseEncodable {}
extension SkillsResponse: ResponseEncodable {}
extension ChatAdaptersResponse: ResponseEncodable {}

public struct SwooshAPISnapshot: Sendable {
    public let startedAt: Date
    public let providers: [ProviderSummary]
    public let activeProviderID: String?
    public let skills: [SkillSummary]

    public init(
        startedAt: Date = Date(),
        providers: [ProviderSummary] = [],
        activeProviderID: String? = nil,
        skills: [SkillSummary] = []
    ) {
        self.startedAt = startedAt
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.skills = skills
    }
}

/// Swoosh HTTP API server. Wraps a Hummingbird application that calls
/// the supplied `AgentKernel` for chat requests.
public struct SwooshAPIServer: Sendable {
    public static let buildVersion: String = "0.9P"

    private let port: Int
    private let hostname: String
    private let token: String?
    private let kernel: KernelHandle?
    private let snapshot: SwooshAPISnapshot

    /// - Parameters:
    ///   - port: TCP port to listen on.
    ///   - hostname: Bind address. `127.0.0.1` keeps the daemon loopback-only;
    ///     `0.0.0.0` exposes it on every interface and should only be used
    ///     when a bearer token is also supplied.
    ///   - token: Bearer token required on every `/api/*` request (except
    ///     `/api/version`). `nil` mounts `DenyAllMiddleware` on the entire
    ///     `/api/*` tree so an accidentally-public daemon is still inert.
    ///   - kernel: Agent kernel that handles chat requests. `nil` makes
    ///     `/api/agent/chat` return 503 — useful in tests that only want to
    ///     exercise routing and auth.
    public init(
        port: Int = 8787,
        hostname: String = "127.0.0.1",
        token: String? = nil,
        kernel: AgentKernel? = nil,
        snapshot: SwooshAPISnapshot = SwooshAPISnapshot()
    ) {
        self.port = port
        self.hostname = hostname
        self.token = token
        self.kernel = kernel.map(KernelHandle.init)
        self.snapshot = snapshot
    }

    /// Build the Hummingbird application with all routes wired in.
    public func build() -> some ApplicationProtocol {
        let router = Router()
        let kernel = self.kernel
        let buildVersion = SwooshAPIServer.buildVersion
        let runtime = APIRuntimeState(snapshot: snapshot)
        let adapterCatalog = ChatAdapterCatalog()
        let adapterToggles = ChatAdapterToggleStore()
        let stateAdapterCatalog = ChatStateAdapterCatalog()
        let stateAdapterToggles = ChatStateAdapterToggleStore()

        // ── Public routes ────────────────────────────────────────────────
        router.get("/health") { _, _ in "ok" }
        router.get("/api/version") { _, _ -> APIVersion in
            APIVersion(name: "Swoosh", version: buildVersion)
        }

        // ── Auth-gated routes ───────────────────────────────────────────
        let apiGroup = router.group("/api")
        if let token {
            apiGroup.add(middleware: BearerAuthMiddleware(token: token))
        } else {
            apiGroup.add(middleware: DenyAllMiddleware())
        }

        apiGroup.post("/agent/chat") { request, context -> ChatResponse in
            guard let kernel else {
                throw HTTPError(.serviceUnavailable, message: "kernel not configured")
            }
            let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
            let agentRequest = AgentRequest(
                sessionID: chatRequest.sessionID,
                input: chatRequest.input
            )
            let agentResponse: AgentResponse
            do {
                agentResponse = try await kernel.kernel.run(agentRequest)
            } catch {
                throw HTTPError(.internalServerError, message: error.localizedDescription)
            }
            await runtime.recordChat(agentResponse)
            return ChatResponse(
                message: agentResponse.message,
                sessionID: agentResponse.sessionID,
                memoryIDsUsed: agentResponse.memoryIDsUsed,
                modelUsed: agentResponse.modelUsed,
                createdAt: agentResponse.createdAt
            )
        }

        apiGroup.get("/agent/status") { _, _ -> AgentStatusResponse in
            await runtime.agentStatus(chatEnabled: kernel != nil)
        }

        apiGroup.get("/providers") { _, _ -> ProvidersResponse in
            await runtime.providers()
        }
        apiGroup.get("/providers/status") { _, _ -> ProviderStatusResponse in
            await runtime.providerStatus()
        }
        apiGroup.get("/board/cards") { _, _ -> BoardCardsResponse in
            await runtime.boardCards(chatEnabled: kernel != nil)
        }
        apiGroup.get("/board/lanes") { _, _ -> BoardLanesResponse in
            await runtime.boardLanes(chatEnabled: kernel != nil)
        }
        apiGroup.get("/metrics") { _, _ -> MetricsResponse in
            await runtime.metrics()
        }
        apiGroup.get("/usage") { _, _ -> UsageResponse in
            await runtime.usage()
        }
        apiGroup.get("/skills") { _, _ -> SkillsResponse in
            await runtime.skills()
        }
        apiGroup.get("/chat-adapters") { _, _ -> ChatAdaptersResponse in
            try await makeChatAdaptersResponse(
                catalog: adapterCatalog,
                store: adapterToggles,
                stateCatalog: stateAdapterCatalog,
                stateStore: stateAdapterToggles
            )
        }
        apiGroup.post("/chat-adapters/toggle") { request, context -> ChatAdaptersResponse in
            let toggle = try await request.decode(as: ChatAdapterToggleRequest.self, context: context)
            if let kind = ChatAdapterKind(rawValue: toggle.id) {
                try await adapterToggles.set(kind, enabled: toggle.enabled)
            } else if let kind = ChatStateAdapterKind(rawValue: toggle.id) {
                try await stateAdapterToggles.set(kind, enabled: toggle.enabled)
            } else {
                throw HTTPError(.badRequest, message: "unknown chat adapter: \(toggle.id)")
            }
            return try await makeChatAdaptersResponse(
                catalog: adapterCatalog,
                store: adapterToggles,
                stateCatalog: stateAdapterCatalog,
                stateStore: stateAdapterToggles
            )
        }

        return Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
    }
}

private func makeChatAdaptersResponse(
    catalog: ChatAdapterCatalog,
    store: ChatAdapterToggleStore,
    stateCatalog: ChatStateAdapterCatalog,
    stateStore: ChatStateAdapterToggleStore
) async throws -> ChatAdaptersResponse {
    let statuses = try await catalog.statuses(store: store)
    let stateStatuses = try await stateCatalog.statuses(store: stateStore)
    return ChatAdapterProjection.response(platformStatuses: statuses, stateStatuses: stateStatuses)
}

/// Sendable handle around `AgentKernel`. The kernel is already an actor, but
/// boxing it in a struct keeps the public `SwooshAPIServer` initializer
/// auto-Sendable.
private struct KernelHandle: Sendable {
    let kernel: AgentKernel
    init(_ kernel: AgentKernel) { self.kernel = kernel }
}

private actor APIRuntimeState {
    private let snapshot: SwooshAPISnapshot
    private var chatTurns = 0
    private var approvedMemoryReferences = 0
    private var lastChatAt: Date?

    init(snapshot: SwooshAPISnapshot) {
        self.snapshot = snapshot
    }

    func recordChat(_ response: AgentResponse) {
        chatTurns += 1
        approvedMemoryReferences += response.memoryIDsUsed.count
        lastChatAt = response.createdAt
    }

    func agentStatus(chatEnabled: Bool) -> AgentStatusResponse {
        let active = activeProvider()
        return AgentStatusResponse(
            status: chatEnabled ? "ready" : "degraded",
            chat: chatEnabled,
            model: active?.model,
            provider: active?.name,
            startedAt: snapshot.startedAt,
            chatTurns: chatTurns,
            lastChatAt: lastChatAt
        )
    }

    func providers() -> ProvidersResponse {
        ProvidersResponse(providers: snapshot.providers, activeProviderID: snapshot.activeProviderID)
    }

    func providerStatus() -> ProviderStatusResponse {
        ProviderStatusResponse(providers: snapshot.providers)
    }

    func boardLanes(chatEnabled: Bool) -> BoardLanesResponse {
        let cards = boardCards(chatEnabled: chatEnabled).cards
        let lanes = [
            BoardLaneSummary(
                id: "runtime",
                title: "Runtime",
                cardCount: cards.filter { $0.laneID == "runtime" }.count
            ),
            BoardLaneSummary(
                id: "configuration",
                title: "Configuration",
                cardCount: cards.filter { $0.laneID == "configuration" }.count
            ),
        ]
        return BoardLanesResponse(lanes: lanes)
    }

    func boardCards(chatEnabled: Bool) -> BoardCardsResponse {
        let now = Date()
        let active = activeProvider()
        var cards = [
            BoardCardSummary(
                id: "daemon",
                laneID: "runtime",
                title: "Daemon",
                detail: chatEnabled ? "HTTP API is accepting chat turns." : "HTTP API is running without an agent kernel.",
                updatedAt: now
            ),
            BoardCardSummary(
                id: "provider",
                laneID: "configuration",
                title: "Model Provider",
                detail: active.map { "\($0.name) \($0.model ?? "")".trimmingCharacters(in: .whitespaces) }
                    ?? "No model provider configured.",
                updatedAt: now
            ),
            BoardCardSummary(
                id: "skills",
                laneID: "configuration",
                title: "Skills",
                detail: "\(snapshot.skills.count) reviewed or promoted skills loaded.",
                updatedAt: now
            ),
        ]
        if let lastChatAt {
            cards.append(BoardCardSummary(
                id: "last-chat",
                laneID: "runtime",
                title: "Last Chat",
                detail: "Last completed chat at \(ISO8601DateFormatter().string(from: lastChatAt)).",
                updatedAt: lastChatAt
            ))
        }
        return BoardCardsResponse(cards: cards)
    }

    func metrics() -> MetricsResponse {
        MetricsResponse(counters: [
            MetricCounter(id: "chat_turns", value: chatTurns),
            MetricCounter(id: "approved_memory_references", value: approvedMemoryReferences),
            MetricCounter(id: "providers", value: snapshot.providers.count),
            MetricCounter(id: "skills", value: snapshot.skills.count),
        ])
    }

    func usage() -> UsageResponse {
        UsageResponse(
            chatTurns: chatTurns,
            approvedMemoryReferences: approvedMemoryReferences,
            lastChatAt: lastChatAt
        )
    }

    func skills() -> SkillsResponse {
        SkillsResponse(skills: snapshot.skills)
    }

    private func activeProvider() -> ProviderSummary? {
        if let activeProviderID = snapshot.activeProviderID {
            return snapshot.providers.first { $0.id == activeProviderID }
        }
        return snapshot.providers.first(where: \.active)
    }
}

public enum APIError: Error, Sendable {
    case notFound(String)
    case unauthorized
    case badRequest(String)
    case internalError(String)
}
