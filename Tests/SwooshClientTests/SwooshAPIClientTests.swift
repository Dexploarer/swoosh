import Foundation
import Testing
@testable import SwooshClient

@Suite("SwooshAPIClient")
struct SwooshAPIClientTests {
    @Test("Health returns true for ok body")
    func healthOK() async throws {
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/health")
            return (200, ["Content-Type": "text/plain"], Data("ok".utf8))
        }) {
            let client = SwooshAPIClient(baseURL: baseURL(), session: MockURLProtocol.makeSession())
            #expect(await client.health())
        }
    }

    @Test("Chat sends bearer token and decodes response")
    func chatSendsBearerAndDecodesResponse() async throws {
        let response = ChatResponse(
            message: "hello from daemon",
            sessionID: "phone",
            memoryIDsUsed: ["mem-1"],
            modelUsed: "swoosh-local-diagnostic-v1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let responseBody = try JSONEncoder.swooshDefault.encode(response)

        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/agent/chat")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pair-token")
            let requestBody = request.bodyData()
            let decoded = try! JSONDecoder.swooshDefault.decode(ChatRequest.self, from: requestBody)
            #expect(decoded.sessionID == "phone")
            #expect(decoded.input == "hello")
            return (200, ["Content-Type": "application/json"], responseBody)
        }) {
            let client = SwooshAPIClient(
                baseURL: baseURL(),
                token: "pair-token",
                session: MockURLProtocol.makeSession()
            )
            let decoded = try await client.chat(ChatRequest(sessionID: "phone", input: "hello"))
            #expect(decoded.message == "hello from daemon")
            #expect(decoded.memoryIDsUsed == ["mem-1"])
        }
    }

    @Test("Status endpoints decode typed responses")
    func statusEndpointsDecodeTypedResponses() async throws {
        let status = AgentStatusResponse(
            status: "ready",
            chat: true,
            model: "swoosh-local-diagnostic-v1",
            provider: "Local Diagnostic Provider",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            chatTurns: 2,
            lastChatAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let providers = ProvidersResponse(
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
        let skills = SkillsResponse(skills: [
            SkillSummary(
                id: "bundled.review",
                title: "Review",
                description: "Review a branch.",
                category: "coding",
                trust: "promoted"
            ),
        ])
        let launchpads = SwooshLaunchpadCatalog.platformsResponse(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )
        let tools = ToolCatalogResponse(
            tools: [
                ToolCatalogToolSummary(
                    id: "jupiter.price",
                    name: "jupiter.price",
                    displayName: "Jupiter Price",
                    description: "Get token prices.",
                    permission: "solana.read",
                    risk: "readOnly",
                    approval: "never",
                    toolset: "solana",
                    platforms: ["macOS"]
                ),
            ],
            toolsets: [
                ToolsetSummary(id: "solana", toolCount: 1, readOnlyCount: 1, writeCount: 0, humanOnlyCount: 0),
            ],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_210)
        )
        let mcp = MCPServersResponse(servers: [
            MCPServerRuntimeSummary(
                id: "pay",
                name: "Pay",
                description: "Paid API wallet",
                enabled: true,
                trustLevel: "userApproved",
                state: "connected",
                transport: "stdio",
                toolCount: 2,
                importedToolCount: 2,
                tools: []
            ),
        ])
        let encoded: [String: Data] = [
            "/api/agent/status": try JSONEncoder.swooshDefault.encode(status),
            "/api/providers": try JSONEncoder.swooshDefault.encode(providers),
            "/api/skills": try JSONEncoder.swooshDefault.encode(skills),
            "/api/tools": try JSONEncoder.swooshDefault.encode(tools),
            "/api/mcp/servers": try JSONEncoder.swooshDefault.encode(mcp),
            "/api/launchpads": try JSONEncoder.swooshDefault.encode(launchpads),
        ]

        try await MockURLProtocol.with({ request in
            let path = request.url?.path ?? ""
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pair-token")
            return (200, ["Content-Type": "application/json"], encoded[path] ?? Data())
        }) {
            let client = SwooshAPIClient(
                baseURL: baseURL(),
                token: "pair-token",
                session: MockURLProtocol.makeSession()
            )
            let decodedStatus = try await client.agentStatus()
            #expect(decodedStatus.chatTurns == 2)
            let decodedProviders = try await client.providers()
            #expect(decodedProviders.activeProviderID == "local-diagnostic")
            let decodedSkills = try await client.skills()
            #expect(decodedSkills.skills.first?.id == "bundled.review")
            let decodedTools = try await client.toolCatalog()
            #expect(decodedTools.tools.first?.name == "jupiter.price")
            let decodedMCP = try await client.mcpServers()
            #expect(decodedMCP.servers.first?.id == "pay")
            let decodedLaunchpads = try await client.launchpads()
            #expect(decodedLaunchpads.platforms.map(\.id).contains("pumpportal"))
            #expect(decodedLaunchpads.platforms.map(\.id).contains("four-meme"))
        }
    }

    @Test("Launchpad detail endpoint decodes typed response")
    func launchpadDetailDecodesTypedResponse() async throws {
        let detail = try #require(SwooshLaunchpadCatalog.detail(
            id: "flap",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_300)
        ))
        let responseBody = try JSONEncoder.swooshDefault.encode(detail)

        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/launchpads/flap")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pair-token")
            return (200, ["Content-Type": "application/json"], responseBody)
        }) {
            let client = SwooshAPIClient(
                baseURL: baseURL(),
                token: "pair-token",
                session: MockURLProtocol.makeSession()
            )
            let decoded = try await client.launchpad(id: "flap")
            #expect(decoded.detail.platform.name == "Flap")
            #expect(decoded.detail.requiredPermissions.contains("evmBuildTransaction"))
        }
    }

    @Test("Transcript sends bearer token and decodes messages")
    func transcriptSendsBearerAndDecodesMessages() async throws {
        let response = TranscriptResponse(
            sessionID: "ios-default",
            messages: [
                TranscriptMessage(
                    id: "m1",
                    role: .user,
                    content: "hello",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                TranscriptMessage(
                    id: "m2",
                    role: .assistant,
                    content: "hi from daemon",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_001)
                ),
            ]
        )
        let responseBody = try JSONEncoder.swooshDefault.encode(response)

        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/agent/transcript/ios-default")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pair-token")
            return (200, ["Content-Type": "application/json"], responseBody)
        }) {
            let client = SwooshAPIClient(
                baseURL: baseURL(),
                token: "pair-token",
                session: MockURLProtocol.makeSession()
            )
            let decoded = try await client.transcript(sessionID: "ios-default")
            #expect(decoded.sessionID == "ios-default")
            #expect(decoded.messages.map(\.role) == [.user, .assistant])
            #expect(decoded.messages.last?.content == "hi from daemon")
        }
    }

    @Test("Readiness endpoint decodes shared report")
    func readinessDecodesSharedReport() async throws {
        let response = SwooshReadinessReport(
            state: .ready,
            summary: "Ready",
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
        let responseBody = try JSONEncoder.swooshDefault.encode(response)

        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/runtime/readiness")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pair-token")
            return (200, ["Content-Type": "application/json"], responseBody)
        }) {
            let client = SwooshAPIClient(
                baseURL: baseURL(),
                token: "pair-token",
                session: MockURLProtocol.makeSession()
            )
            let decoded = try await client.readiness()
            #expect(decoded.state == .ready)
            #expect(decoded.component(id: "daemon.chat")?.status == .ready)
        }
    }

    @Test("Server error decodes APIErrorBody")
    func serverErrorDecodesEnvelope() async throws {
        let body = try JSONEncoder.swooshDefault.encode(APIErrorBody(error: "missing or invalid bearer token", code: "unauthorized"))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/version")
            return (401, ["Content-Type": "application/json"], body)
        }) {
            let client = SwooshAPIClient(baseURL: baseURL(), session: MockURLProtocol.makeSession())
            do {
                _ = try await client.version()
                Issue.record("version should throw")
            } catch SwooshClientError.server(let status, let message) {
                #expect(status == 401)
                #expect(message == "missing or invalid bearer token")
            }
        }
    }

    private func baseURL() -> URL {
        URL(string: "http://127.0.0.1:8787/")!
    }
}
