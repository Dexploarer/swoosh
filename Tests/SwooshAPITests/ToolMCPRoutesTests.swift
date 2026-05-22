// Tests/SwooshAPITests/ToolMCPRoutesTests.swift — Tier 1
//
// Wire-level coverage for /api/tools/:name/execute and the /api/mcp/*
// CRUD endpoints. Runtime callbacks return canned payloads; assertions
// verify routing + serialization.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

@Suite("Tool exec route")
struct ToolExecRouteTests {

    @Test("POST /api/tools/:name/execute returns typed output")
    func executeToolHappyPath() async throws {
        let receivedName = ToolExecNameBox()
        let receivedReq = ToolExecRequestBox()
        let sources = SwooshAPIRuntimeSources(
            executeTool: { name, request in
                await receivedName.set(name)
                await receivedReq.set(request)
                return ToolExecuteResponse(
                    toolName: name,
                    success: true,
                    outputJSON: "{\"ok\":true}",
                    error: nil,
                    durationMs: 12
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(
                ToolExecuteRequest(argsJSON: "{\"x\":1}", sessionID: "s")
            )
            try await client.execute(
                uri: "/api/tools/core.status/execute", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(ToolExecuteResponse.self, from: Data(buffer: response.body))
                #expect(decoded.success)
                #expect(decoded.outputJSON == "{\"ok\":true}")
            }
        }
        #expect(await receivedName.value == "core.status")
        #expect(await receivedReq.value?.argsJSON == "{\"x\":1}")
        #expect(await receivedReq.value?.sessionID == "s")
    }

    @Test("POST /api/tools/:name/execute surfaces errors as success=false")
    func executeToolError() async throws {
        let sources = SwooshAPIRuntimeSources(
            executeTool: { name, _ in
                ToolExecuteResponse(
                    toolName: name,
                    success: false,
                    outputJSON: nil,
                    error: "boom",
                    durationMs: 1
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(ToolExecuteRequest())
            try await client.execute(
                uri: "/api/tools/nope/execute", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(ToolExecuteResponse.self, from: Data(buffer: response.body))
                #expect(!decoded.success)
                #expect(decoded.error == "boom")
            }
        }
    }
}

@Suite("MCP CRUD routes")
struct MCPCRUDRoutesTests {

    @Test("POST /api/mcp/servers invokes addMCPServer")
    func addMCPServer() async throws {
        let received = MCPCreateBox()
        let sources = SwooshAPIRuntimeSources(
            addMCPServer: { request in
                await received.set(request)
                return MCPServerMutationResponse(
                    server: sampleMCPServer(id: request.id),
                    message: "MCP server registered."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(MCPServerCreateRequest(
                id: "abc", name: "Abc", transport: "stdio", command: "/bin/echo"
            ))
            try await client.execute(
                uri: "/api/mcp/servers", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(MCPServerMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.server.id == "abc")
            }
        }
        #expect(await received.value?.id == "abc")
        #expect(await received.value?.command == "/bin/echo")
    }

    @Test("DELETE /api/mcp/servers/:id maps to removeMCPServer")
    func removeMCPServer() async throws {
        let captured = MCPIDBox()
        let sources = SwooshAPIRuntimeSources(
            removeMCPServer: { id in
                await captured.set(id)
                return MCPServersResponse(servers: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/mcp/servers/abc", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(MCPServersResponse.self, from: Data(buffer: response.body))
                #expect(decoded.servers.isEmpty)
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("POST /api/mcp/servers/:id/connect enables server")
    func connectMCPServer() async throws {
        let captured = MCPIDBox()
        let sources = SwooshAPIRuntimeSources(
            connectMCPServer: { id in
                await captured.set(id)
                return MCPServerMutationResponse(
                    server: sampleMCPServer(id: id, enabled: true, state: "connected"),
                    message: "MCP server enabled."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/mcp/servers/abc/connect", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(MCPServerMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.server.enabled)
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("POST /api/mcp/servers/:id/disconnect disables server")
    func disconnectMCPServer() async throws {
        let captured = MCPIDBox()
        let sources = SwooshAPIRuntimeSources(
            disconnectMCPServer: { id in
                await captured.set(id)
                return MCPServerMutationResponse(
                    server: sampleMCPServer(id: id, enabled: false, state: "disabled"),
                    message: "MCP server disabled."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/mcp/servers/abc/disconnect", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(MCPServerMutationResponse.self, from: Data(buffer: response.body))
                #expect(!decoded.server.enabled)
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("GET /api/mcp/servers/:id/tools returns tools per server")
    func mcpServerTools() async throws {
        let sources = SwooshAPIRuntimeSources(
            mcpServerTools: { id in
                MCPServerToolsResponse(
                    serverID: id,
                    tools: [
                        MCPDiscoveredToolSummary(
                            id: "t1", name: "search",
                            title: "Search", description: "Search the web",
                            estimatedRisk: "readOnly"
                        )
                    ]
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/mcp/servers/abc/tools", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try toolMCPTestDecoder().decode(MCPServerToolsResponse.self, from: Data(buffer: response.body))
                #expect(body.serverID == "abc")
                #expect(body.tools.first?.name == "search")
            }
        }
    }
}

private func sampleMCPServer(
    id: String,
    enabled: Bool = false,
    state: String = "configured"
) -> MCPServerRuntimeSummary {
    MCPServerRuntimeSummary(
        id: id,
        name: "Test \(id)",
        description: nil,
        enabled: enabled,
        trustLevel: "untrusted",
        state: state,
        transport: "stdio",
        toolCount: 0,
        importedToolCount: 0,
        tools: []
    )
}

private actor ToolExecNameBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor ToolExecRequestBox {
    private var stored: ToolExecuteRequest?
    func set(_ value: ToolExecuteRequest) { stored = value }
    var value: ToolExecuteRequest? { stored }
}

private actor MCPIDBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor MCPCreateBox {
    private var stored: MCPServerCreateRequest?
    func set(_ value: MCPServerCreateRequest) { stored = value }
    var value: MCPServerCreateRequest? { stored }
}

private func toolMCPTestDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
