import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
import NIOCore
@testable import SwooshAPI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshTools
import SwooshFirewall
import SwooshApprovals

struct APIMemoryLoader: MemoryContextLoading {
    func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)] { [] }
}

struct APIReportLoader: SetupReportLoading {
    func loadLatestSetupReport() async throws -> String? { nil }
}

struct APIPermissionSummarizer: PermissionSummarizing {
    func permissionSummary() async throws -> String { "All permissions granted" }
}

actor APISessionStore: SessionStoring {
    private var messages: [String: [SwooshCore.ChatMessage]] = [:]

    init(messages: [String: [SwooshCore.ChatMessage]] = [:]) {
        self.messages = messages
    }

    func appendMessage(sessionID: String, message: SwooshCore.ChatMessage) async throws {
        messages[sessionID, default: []].append(message)
    }

    func loadTranscript(sessionID: String) async throws -> [SwooshCore.ChatMessage] {
        messages[sessionID] ?? []
    }
}

actor APIResponseAuditor: ResponseAuditing {
    func logResponseAudit(_ audit: ResponseAuditRecord) async throws {}
    func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord? { nil }
}

actor APIFirewall: SwooshTools.Firewall {
    func require(_ permission: SwooshPermission) async throws {}
    func isGranted(_ permission: SwooshPermission) async -> Bool { true }
}

actor APIApproval: ApprovalRequesting {
    func requireApproval(_ request: ToolApprovalRequest) async throws {}
    func listPending() async -> [ToolApprovalRequest] { [] }
    func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {}
}

struct APIStatusTool: SwooshTool {
    typealias Input = APIEmptyInput
    typealias Output = APIStatusOutput

    static let name: ToolName = "core.status"
    static let displayName = "Status"
    static let description = "Returns system status"
    static let permission: SwooshPermission = .deviceProfileRead
    static let risk: ToolRisk = .readOnly
    static let approval: ApprovalPolicy = .never
    static let toolset: ToolsetID = .core

    func call(_ input: APIEmptyInput, context: ToolContext) async throws -> APIStatusOutput {
        APIStatusOutput(status: "ok")
    }
}

struct APIEmptyInput: Codable, Sendable {}
struct APIStatusOutput: Codable, Sendable { let status: String }

actor APIToolCallingProvider: ModelProvider {
    nonisolated let providerID = "api-test"
    nonisolated let modelName = "api-test-model"
    private var calls = 0
    private var toolCounts: [Int] = []

    func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        calls += 1
        toolCounts.append(request.tools.count)
        if calls == 1 {
            return ModelCompletionResponse(
                content: "",
                model: modelName,
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            )
        }
        return ModelCompletionResponse(content: "API tool loop answered.", model: modelName)
    }

    func capturedToolCounts() -> [Int] {
        toolCounts
    }
}

@Suite("Swoosh API routes")
struct SwooshServerTests {
    @Test("Runtime surfaces return typed state")
    func runtimeSurfacesReturnState() async throws {
        let snapshot = SwooshAPISnapshot(
            providers: [
                ProviderSummary(
                    id: "local-diagnostic",
                    name: "Local Diagnostic Provider",
                    model: "swoosh-local-diagnostic-v1",
                    configured: true,
                    active: true,
                    status: "active"
                ),
            ],
            activeProviderID: "local-diagnostic",
            skills: [
                SkillSummary(
                    id: "bundled.review",
                    title: "Review",
                    description: "Review the current branch.",
                    category: "coding",
                    trust: "promoted"
                ),
            ]
        )
        let app = SwooshAPIServer(token: "secret", snapshot: snapshot).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/providers",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(
                uri: "/api/skills",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(
                uri: "/api/board/cards",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(
                uri: "/api/metrics",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("Runtime sources override startup snapshot")
    func runtimeSourcesOverrideSnapshot() async throws {
        let snapshot = SwooshAPISnapshot(
            providers: [
                ProviderSummary(
                    id: "stale",
                    name: "Stale",
                    model: nil,
                    configured: false,
                    active: false,
                    status: "missing"
                ),
            ],
            activeProviderID: "stale",
            skills: []
        )
        let sources = SwooshAPIRuntimeSources(
            providers: {
                ProvidersResponse(
                    providers: [
                        ProviderSummary(
                            id: "local-diagnostic",
                            name: "Local Diagnostic Provider",
                            model: "swoosh-local-diagnostic-v1",
                            configured: true,
                            active: true,
                            status: "active"
                        ),
                    ],
                    activeProviderID: "local-diagnostic"
                )
            },
            skills: {
                SkillsResponse(skills: [
                    SkillSummary(
                        id: "bundled.local",
                        title: "Local Skill",
                        description: "Runs locally.",
                        category: "coding",
                        trust: "reviewed"
                    ),
                ])
            }
        )
        let app = SwooshAPIServer(token: "secret", snapshot: snapshot, runtimeSources: sources).build()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/metrics",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                guard let data = response.body.getData(
                    at: response.body.readerIndex,
                    length: response.body.readableBytes
                ) else {
                    Issue.record("Missing metrics response body")
                    return
                }
                let decoded = try JSONDecoder.swooshDefault.decode(MetricsResponse.self, from: data)
                #expect(decoded.counters.first { $0.id == "providers" }?.value == 1)
                #expect(decoded.counters.first { $0.id == "skills" }?.value == 1)
            }
            try await client.execute(
                uri: "/api/providers",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                guard let data = response.body.getData(
                    at: response.body.readerIndex,
                    length: response.body.readableBytes
                ) else {
                    Issue.record("Missing providers response body")
                    return
                }
                let decoded = try JSONDecoder.swooshDefault.decode(ProvidersResponse.self, from: data)
                #expect(decoded.activeProviderID == "local-diagnostic")
                #expect(decoded.providers.first?.id == "local-diagnostic")
            }
        }
    }

    @Test("Runtime readiness route uses shared source")
    func runtimeReadinessRouteUsesSharedSource() async throws {
        let report = SwooshReadinessReport(
            state: .ready,
            summary: "Ready from source",
            components: [
                SwooshReadinessComponent(
                    id: "daemon.chat",
                    title: "Daemon chat",
                    status: .ready,
                    detail: "chat enabled"
                ),
            ],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let app = SwooshAPIServer(
            token: "secret",
            runtimeSources: SwooshAPIRuntimeSources(readiness: { report })
        ).build()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/runtime/readiness",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                guard let data = response.body.getData(
                    at: response.body.readerIndex,
                    length: response.body.readableBytes
                ) else {
                    Issue.record("Missing readiness response body")
                    return
                }
                let decoded = try JSONDecoder.swooshDefault.decode(SwooshReadinessReport.self, from: data)
                #expect(decoded.state == .ready)
                #expect(decoded.summary == "Ready from source")
            }
        }
    }

    @Test("Auth-gated chat rejects missing bearer token")
    func chatRejectsMissingBearer() async throws {
        let app = SwooshAPIServer(token: "secret").build()
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/agent/chat", method: .post) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Transcript route returns persisted session messages")
    func transcriptRouteReturnsPersistedSessionMessages() async throws {
        let store = APISessionStore(messages: [
            "ios-default": [
                SwooshCore.ChatMessage(
                    id: "m1",
                    role: .user,
                    content: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                SwooshCore.ChatMessage(
                    id: "m2",
                    role: .assistant,
                    content: "hi from the Mac",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_001)
                ),
            ],
        ])
        let kernel = AgentKernel(
            memoryLoader: APIMemoryLoader(),
            reportLoader: APIReportLoader(),
            permSummarizer: APIPermissionSummarizer(),
            sessionStore: store,
            auditLogger: APIResponseAuditor(),
            modelProvider: LocalDiagnosticProvider()
        )
        let app = SwooshAPIServer(token: "secret", kernel: kernel).build()

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/agent/transcript/ios-default",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                guard let data = response.body.getData(
                    at: response.body.readerIndex,
                    length: response.body.readableBytes
                ) else {
                    Issue.record("Missing transcript response body")
                    return
                }
                let decoded = try JSONDecoder.swooshDefault.decode(TranscriptResponse.self, from: data)
                #expect(decoded.sessionID == "ios-default")
                #expect(decoded.messages.map(\.id) == ["m1", "m2"])
                #expect(decoded.messages.map(\.role) == [.user, .assistant])
            }
        }
    }

    @Test("Chat route uses configured tool loop")
    func chatRouteUsesConfiguredToolLoop() async throws {
        let registry = ToolRegistry(firewall: APIFirewall(), audit: SwooshAuditLog(), approvals: APIApproval())
        await registry.register(TypeErasedTool(APIStatusTool()))
        let provider = APIToolCallingProvider()
        let loop = AgentToolLoop(
            memoryLoader: APIMemoryLoader(),
            reportLoader: APIReportLoader(),
            permSummarizer: APIPermissionSummarizer(),
            sessionStore: APISessionStore(),
            auditLogger: APIResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry
        )
        let app = SwooshAPIServer(token: "secret", toolLoop: loop).build()
        let request = ChatRequest(sessionID: "api", input: "status")
        let data = try JSONEncoder.swooshDefault.encode(request)
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        let body = buffer

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/agent/chat",
                method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: body
            ) { response in
                #expect(response.status == .ok)
                guard let responseData = response.body.getData(
                    at: response.body.readerIndex,
                    length: response.body.readableBytes
                ) else {
                    Issue.record("Missing response body")
                    return
                }
                let decoded = try JSONDecoder.swooshDefault.decode(ChatResponse.self, from: responseData)
                #expect(decoded.message == "API tool loop answered.")
            }
        }
        let counts = await provider.capturedToolCounts()
        #expect(counts.first == 1)
    }
}
