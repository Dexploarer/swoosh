// SwooshAPI/SwooshServer.swift — HTTP API server
//
// Hummingbird router with three layers:
//
//   1. Public routes  — `/health`, `/api/version`. No auth, safe to expose.
//   2. Auth-gated     — every other `/api/*` route. Requires a bearer token.
//                       When the daemon was started without one, the entire
//                       `/api/*` tree is shadow-mounted under DenyAllMiddleware
//                       so binding to 0.0.0.0 still can't expose the agent.
//   3. Agent          — `POST /api/agent/chat` calls the tool loop when it is
//                       configured, otherwise the plain kernel.
//
// Streaming / WebSocket and the audit/approvals endpoints will land on top of
// this once the iOS slice is proven; this file is intentionally the smallest
// thing that gives the phone a real conversation.

import Foundation
import Hummingbird
import SwooshCore
import SwooshClient
import SwooshChatSDK
import SwooshConfig

// Server-side conformance so `ChatResponse` can be returned from a Hummingbird
// route directly. `SwooshClient` itself doesn't import Hummingbird.
extension ChatResponse: ResponseEncodable {}
extension TranscriptResponse: ResponseEncodable {}
extension APIErrorBody: ResponseEncodable {}
extension APIVersion: ResponseEncodable {}
extension AgentStatusResponse: ResponseEncodable {}
extension SwooshReadinessReport: ResponseEncodable {}
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

public struct SwooshAPIRuntimeSources: Sendable {
    public let providers: @Sendable () async -> ProvidersResponse?
    public let skills: @Sendable () async -> SkillsResponse?
    public let readiness: @Sendable () async -> SwooshReadinessReport?

    public init(
        providers: @escaping @Sendable () async -> ProvidersResponse? = { nil },
        skills: @escaping @Sendable () async -> SkillsResponse? = { nil },
        readiness: @escaping @Sendable () async -> SwooshReadinessReport? = { nil }
    ) {
        self.providers = providers
        self.skills = skills
        self.readiness = readiness
    }
}

/// Swoosh HTTP API server. Wraps a Hummingbird application that calls
/// the supplied `AgentKernel` for chat requests.
public struct SwooshAPIServer: Sendable {
    public static let buildVersion: String = "0.9P"

    private let port: Int
    private let hostname: String
    private let token: String?
    private let agent: AgentHandle?
    private let snapshot: SwooshAPISnapshot
    private let runtimeSources: SwooshAPIRuntimeSources

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
        toolLoop: AgentToolLoop? = nil,
        snapshot: SwooshAPISnapshot = SwooshAPISnapshot(),
        runtimeSources: SwooshAPIRuntimeSources = SwooshAPIRuntimeSources()
    ) {
        self.port = port
        self.hostname = hostname
        self.token = token
        if let toolLoop {
            self.agent = .toolLoop(ToolLoopHandle(toolLoop))
        } else if let kernel {
            self.agent = .kernel(KernelHandle(kernel))
        } else {
            self.agent = nil
        }
        self.snapshot = snapshot
        self.runtimeSources = runtimeSources
    }

    /// Build the Hummingbird application with all routes wired in.
    public func build() -> some ApplicationProtocol {
        let router = Router()
        let agent = self.agent
        let buildVersion = SwooshAPIServer.buildVersion
        let runtime = APIRuntimeState(snapshot: snapshot, sources: runtimeSources)
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
            guard let agent else {
                throw HTTPError(.serviceUnavailable, message: "kernel not configured")
            }
            let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
            let agentRequest = AgentRequest(
                sessionID: chatRequest.sessionID,
                input: chatRequest.input
            )
            let agentResponse: AgentResponse
            do {
                agentResponse = try await agent.run(agentRequest)
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

        apiGroup.get("/agent/transcript/:sessionID") { _, context -> TranscriptResponse in
            guard let agent else {
                throw HTTPError(.serviceUnavailable, message: "kernel not configured")
            }
            let sessionID = try context.parameters.require("sessionID", as: String.self)
            do {
                let transcript = try await agent.loadTranscript(sessionID: sessionID)
                return TranscriptResponse(
                    sessionID: sessionID,
                    messages: transcript.map(transcriptMessage)
                )
            } catch {
                throw HTTPError(.internalServerError, message: error.localizedDescription)
            }
        }

        apiGroup.get("/agent/status") { _, _ -> AgentStatusResponse in
            await runtime.agentStatus(chatEnabled: agent != nil)
        }

        apiGroup.get("/runtime/readiness") { _, _ -> SwooshReadinessReport in
            await runtime.readiness(chatEnabled: agent != nil)
        }

        apiGroup.get("/providers") { _, _ -> ProvidersResponse in
            await runtime.providers()
        }
        apiGroup.get("/providers/status") { _, _ -> ProviderStatusResponse in
            await runtime.providerStatus()
        }
        apiGroup.get("/board/cards") { _, _ -> BoardCardsResponse in
            await runtime.boardCards(chatEnabled: agent != nil)
        }
        apiGroup.get("/board/lanes") { _, _ -> BoardLanesResponse in
            await runtime.boardLanes(chatEnabled: agent != nil)
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

private struct ToolLoopHandle: Sendable {
    let loop: AgentToolLoop
    init(_ loop: AgentToolLoop) { self.loop = loop }
}

private enum AgentHandle: Sendable {
    case kernel(KernelHandle)
    case toolLoop(ToolLoopHandle)

    func run(_ request: AgentRequest) async throws -> AgentResponse {
        switch self {
        case .kernel(let handle):
            return try await handle.kernel.run(request)
        case .toolLoop(let handle):
            return try await handle.loop.run(request).agentResponse
        }
    }

    func loadTranscript(sessionID: String) async throws -> [SwooshCore.ChatMessage] {
        switch self {
        case .kernel(let handle):
            return try await handle.kernel.loadTranscript(sessionID: sessionID)
        case .toolLoop(let handle):
            return try await handle.loop.loadTranscript(sessionID: sessionID)
        }
    }
}

private func transcriptMessage(_ message: SwooshCore.ChatMessage) -> TranscriptMessage {
    TranscriptMessage(
        id: message.id,
        role: transcriptRole(message.role),
        content: message.content,
        createdAt: message.createdAt
    )
}

private func transcriptRole(_ role: SwooshCore.ChatRole) -> TranscriptRole {
    switch role {
    case .system:
        return .system
    case .user:
        return .user
    case .assistant:
        return .assistant
    case .tool:
        return .tool
    }
}

private actor APIRuntimeState {
    private let snapshot: SwooshAPISnapshot
    private let sources: SwooshAPIRuntimeSources
    private var chatTurns = 0
    private var approvedMemoryReferences = 0
    private var lastChatAt: Date?

    init(snapshot: SwooshAPISnapshot, sources: SwooshAPIRuntimeSources) {
        self.snapshot = snapshot
        self.sources = sources
    }

    func recordChat(_ response: AgentResponse) {
        chatTurns += 1
        approvedMemoryReferences += response.memoryIDsUsed.count
        lastChatAt = response.createdAt
    }

    func agentStatus(chatEnabled: Bool) async -> AgentStatusResponse {
        let active = await activeProvider()
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

    func providers() async -> ProvidersResponse {
        await sources.providers() ?? ProvidersResponse(
            providers: snapshot.providers,
            activeProviderID: snapshot.activeProviderID
        )
    }

    func readiness(chatEnabled: Bool) async -> SwooshReadinessReport {
        if let readiness = await sources.readiness() {
            return readiness
        }
        let active = await activeProvider()
        let skills = await skills()
        return SwooshReadinessDetector().report(inputs: SwooshReadinessInputs(
            daemonReachable: true,
            chatEnabled: chatEnabled,
            activeProviderName: active?.name,
            activeModel: active?.model,
            promptableSkillCount: skills.skills.count
        ))
    }

    func providerStatus() async -> ProviderStatusResponse {
        ProviderStatusResponse(providers: await providers().providers)
    }

    func boardLanes(chatEnabled: Bool) async -> BoardLanesResponse {
        let cards = await boardCards(chatEnabled: chatEnabled).cards
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

    func boardCards(chatEnabled: Bool) async -> BoardCardsResponse {
        let now = Date()
        let active = await activeProvider()
        let skills = await skills()
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
                detail: "\(skills.skills.count) reviewed or promoted skills loaded.",
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

    func metrics() async -> MetricsResponse {
        let providerCount = await providers().providers.count
        let skillCount = await skills().skills.count
        return MetricsResponse(counters: [
            MetricCounter(id: "chat_turns", value: chatTurns),
            MetricCounter(id: "approved_memory_references", value: approvedMemoryReferences),
            MetricCounter(id: "providers", value: providerCount),
            MetricCounter(id: "skills", value: skillCount),
        ])
    }

    func usage() -> UsageResponse {
        UsageResponse(
            chatTurns: chatTurns,
            approvedMemoryReferences: approvedMemoryReferences,
            lastChatAt: lastChatAt
        )
    }

    func skills() async -> SkillsResponse {
        await sources.skills() ?? SkillsResponse(skills: snapshot.skills)
    }

    private func activeProvider() async -> ProviderSummary? {
        let current = await providers()
        if let activeProviderID = current.activeProviderID {
            return current.providers.first { $0.id == activeProviderID }
        }
        return current.providers.first(where: \.active)
    }
}

public enum APIError: Error, Sendable {
    case notFound(String)
    case unauthorized
    case badRequest(String)
    case internalError(String)
}
