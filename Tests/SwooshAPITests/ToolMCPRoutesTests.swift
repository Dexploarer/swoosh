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
import SwooshFirewall
import SwooshToolsets
import SwooshTools

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

    @Test("Swoosh API exposes and runs connector.status through the real ToolRegistry path")
    func connectorStatusExposedAndExecutable() async throws {
        let firewall = SwooshFirewallActor(granted: [.toolRead])
        let audit = SwooshAuditLog()
        let approvals = InMemoryApprovalRequester(autoApprove: true)
        let dependencies = ToolDependencies(
            firewall: firewall,
            audit: audit,
            approvals: approvals,
            fileAccess: APITestFileAccess(),
            processRunner: APITestProcessRunner()
        )
        let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(ConnectorStatusTool(dependencies: dependencies)))
        let sources = SwooshAPIRuntimeSources(
            tools: {
                await connectorAPITestCatalog(registry: registry)
            },
            executeTool: { name, request in
                let input = try connectorAPITestDecodeArgs(request.argsJSON)
                let output = try await registry.call(
                    name: ToolName(name),
                    input: input,
                    context: ToolContext(sessionID: request.sessionID ?? "api-test", isModelInvocation: false)
                )
                let data = try JSONEncoder().encode(output)
                return ToolExecuteResponse(
                    toolName: name,
                    success: true,
                    outputJSON: String(data: data, encoding: .utf8),
                    error: nil,
                    durationMs: 1
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/tools",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(ToolCatalogResponse.self, from: Data(buffer: response.body))
                #expect(decoded.tools.contains { $0.name == "connector.status" && $0.toolset == "connectors" })
            }

            let body = try JSONEncoder().encode(
                ToolExecuteRequest(argsJSON: "{\"connectorID\":\"web\"}", sessionID: "connector-api-test")
            )
            try await client.execute(
                uri: "/api/tools/connector.status/execute",
                method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try toolMCPTestDecoder().decode(ToolExecuteResponse.self, from: Data(buffer: response.body))
                #expect(decoded.success)
                #expect(decoded.outputJSON?.contains("\"id\":\"web\"") == true)
                #expect(decoded.outputJSON?.contains("\"usable\":true") == true)
            }
        }
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

private func connectorAPITestCatalog(registry: ToolRegistry) async -> ToolCatalogResponse {
    let descriptors = await registry.listAvailable(context: ToolContext(sessionID: "api-test", isModelInvocation: false))
    let tools = descriptors.map { descriptor in
        ToolCatalogToolSummary(
            id: descriptor.id,
            name: descriptor.name,
            displayName: descriptor.displayName,
            description: descriptor.description,
            permission: descriptor.permission.rawValue,
            risk: descriptor.risk.rawValue,
            approval: connectorAPITestApprovalLabel(descriptor.approval),
            toolset: descriptor.toolset.rawValue,
            platforms: descriptor.platforms.map(\.rawValue).sorted()
        )
    }
    let toolsets = Dictionary(grouping: descriptors, by: \.toolset.rawValue).map { id, grouped in
        ToolsetSummary(
            id: id,
            toolCount: grouped.count,
            readOnlyCount: grouped.filter { $0.risk == .readOnly }.count,
            writeCount: grouped.filter { $0.risk != .readOnly }.count,
            humanOnlyCount: grouped.filter { $0.approval == .humanOnly }.count
        )
    }
    return ToolCatalogResponse(tools: tools, toolsets: toolsets)
}

private func connectorAPITestDecodeArgs(_ raw: String) throws -> JSONValue {
    guard !raw.isEmpty, let data = raw.data(using: .utf8) else {
        return .object([:])
    }
    return try JSONDecoder().decode(JSONValue.self, from: data)
}

private func connectorAPITestApprovalLabel(_ policy: ApprovalPolicy) -> String {
    switch policy {
    case .never: return "never"
    case .askFirstTime: return "askFirstTime"
    case .askEveryTime: return "askEveryTime"
    case .askForRiskAtLeast(let risk): return "askForRiskAtLeast:\(risk.rawValue)"
    case .humanOnly: return "humanOnly"
    case .disabled: return "disabled"
    }
}

private struct APITestFileAccess: FileAccessing {
    func resolveBookmark(id: String) async throws -> URL {
        throw ToolError.executionFailed("file access unavailable in API test")
    }

    func listDirectory(root: URL, relativePath: String?, includeHidden: Bool, maxDepth: Int) async throws -> [FileEntry] {
        throw ToolError.executionFailed("file access unavailable in API test")
    }

    func readFile(root: URL, relativePath: String, maxBytes: Int?) async throws -> (content: String, truncated: Bool, redaction: RedactionReport?) {
        throw ToolError.executionFailed("file access unavailable in API test")
    }

    func writeFile(root: URL, relativePath: String, content: String, createBackup: Bool) async throws -> (bytesWritten: Int64, backupPath: String?) {
        throw ToolError.executionFailed("file access unavailable in API test")
    }

    func deleteFile(root: URL, relativePath: String) async throws {
        throw ToolError.executionFailed("file access unavailable in API test")
    }

    func searchFiles(root: URL, query: String, filePattern: String?, maxResults: Int?) async throws -> [FileSearchMatch] {
        throw ToolError.executionFailed("file access unavailable in API test")
    }
}

private struct APITestProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String], workingDirectory: URL?, environment: [String: String]?) async throws -> ProcessResult {
        ProcessResult(exitCode: 127, stdout: "", stderr: "process runner unavailable in API test")
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
                id: "abc",
                name: "Abc",
                transport: "stdio",
                command: "/bin/echo",
                environmentSecretRefs: ["TOKEN": "abc.token"]
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
        #expect(await received.value?.environmentSecretRefs == ["TOKEN": "abc.token"])
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
