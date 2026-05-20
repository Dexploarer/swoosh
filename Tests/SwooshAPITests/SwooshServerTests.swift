import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
import NIOCore
@testable import SwooshAPI
import SwooshClient
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
    func appendMessage(sessionID: String, message: SwooshCore.ChatMessage) async throws {}
    func loadTranscript(sessionID: String) async throws -> [SwooshCore.ChatMessage] { [] }
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

    @Test("Auth-gated chat rejects missing bearer token")
    func chatRejectsMissingBearer() async throws {
        let app = SwooshAPIServer(token: "secret").build()
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/agent/chat", method: .post) { response in
                #expect(response.status == .unauthorized)
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
