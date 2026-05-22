// SwooshDaemon/MCPAPIBridge.swift — MCP registry ↔ HTTP API
//
// CRUD on `MCPServerRegistry` server profiles plus per-server tool
// listing. Connect/disconnect map to enable/disable so the existing
// trust + audit + import pipeline runs through the firewall path.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshMCP
import SwooshTools

extension SwooshDaemon {

    static func mcpServerRuntimeSummary(
        _ profile: MCPServerProfile,
        registry: MCPServerRegistry
    ) async -> MCPServerRuntimeSummary {
        let tools = await registry.listTools(serverID: profile.id)
        var toolSummaries: [MCPDiscoveredToolSummary] = []
        toolSummaries.reserveCapacity(tools.count)
        for tool in tools {
            let risk = await registry.classifyToolRisk(serverID: profile.id, toolName: tool.name)
            toolSummaries.append(MCPDiscoveredToolSummary(
                id: tool.id,
                name: tool.name,
                title: tool.title,
                description: tool.description,
                estimatedRisk: risk.rawValue
            ))
        }
        let importedCount = await registry.importedToolNames(serverID: profile.id).count
        return MCPServerRuntimeSummary(
            id: profile.id,
            name: profile.name,
            description: profile.description,
            enabled: profile.enabled,
            trustLevel: profile.trustLevel.rawValue,
            state: profile.state.rawValue,
            transport: transportLabel(profile.transport),
            toolCount: tools.count,
            importedToolCount: importedCount,
            tools: toolSummaries.sorted { $0.name < $1.name }
        )
    }

    static func mcpToolSummary(
        _ tool: MCPToolDescriptor,
        registry: MCPServerRegistry,
        serverID: String
    ) async -> MCPDiscoveredToolSummary {
        let risk = await registry.classifyToolRisk(serverID: serverID, toolName: tool.name)
        return MCPDiscoveredToolSummary(
            id: tool.id,
            name: tool.name,
            title: tool.title,
            description: tool.description,
            estimatedRisk: risk.rawValue
        )
    }

    static func addMCPServerResponse(
        registry: MCPServerRegistry,
        request: MCPServerCreateRequest
    ) async throws -> MCPServerMutationResponse {
        let trimmedID = request.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw APIError.badRequest("MCP server id is empty")
        }
        let transport = try makeTransport(request)
        let trust = try parseTrust(request.trustLevel)
        let profile = MCPServerProfile(
            id: trimmedID,
            name: request.name.isEmpty ? trimmedID : request.name,
            description: request.description,
            transport: transport,
            state: .configured,
            trustLevel: trust,
            enabled: request.enabled ?? false
        )
        do {
            try await registry.addServer(profile)
        } catch {
            throw APIError.badRequest("could not add MCP server: \(error.localizedDescription)")
        }
        let summary = await mcpServerRuntimeSummary(profile, registry: registry)
        return MCPServerMutationResponse(server: summary, message: "MCP server registered.")
    }

    static func removeMCPServerResponse(
        registry: MCPServerRegistry,
        id: String
    ) async throws -> MCPServersResponse {
        guard await registry.getServer(id) != nil else {
            throw APIError.notFound("MCP server not found: \(id)")
        }
        do {
            try await registry.removeServer(id)
        } catch {
            throw APIError.badRequest("could not remove MCP server: \(error.localizedDescription)")
        }
        return await mcpServersResponse(registry: registry)
    }

    static func connectMCPServerResponse(
        registry: MCPServerRegistry,
        id: String
    ) async throws -> MCPServerMutationResponse {
        guard let _ = await registry.getServer(id) else {
            throw APIError.notFound("MCP server not found: \(id)")
        }
        do {
            try await registry.enableServer(id)
        } catch {
            throw APIError.badRequest("could not enable MCP server: \(error.localizedDescription)")
        }
        guard let profile = await registry.getServer(id) else {
            throw APIError.notFound("MCP server not found after enable: \(id)")
        }
        let summary = await mcpServerRuntimeSummary(profile, registry: registry)
        return MCPServerMutationResponse(server: summary, message: "MCP server enabled.")
    }

    static func disconnectMCPServerResponse(
        registry: MCPServerRegistry,
        id: String
    ) async throws -> MCPServerMutationResponse {
        guard let _ = await registry.getServer(id) else {
            throw APIError.notFound("MCP server not found: \(id)")
        }
        do {
            try await registry.disableServer(id)
        } catch {
            throw APIError.badRequest("could not disable MCP server: \(error.localizedDescription)")
        }
        guard let profile = await registry.getServer(id) else {
            throw APIError.notFound("MCP server not found after disable: \(id)")
        }
        let summary = await mcpServerRuntimeSummary(profile, registry: registry)
        return MCPServerMutationResponse(server: summary, message: "MCP server disabled.")
    }

    static func mcpServerToolsResponse(
        registry: MCPServerRegistry,
        id: String
    ) async throws -> MCPServerToolsResponse {
        guard await registry.getServer(id) != nil else {
            throw APIError.notFound("MCP server not found: \(id)")
        }
        let tools = await registry.listTools(serverID: id)
        var summaries: [MCPDiscoveredToolSummary] = []
        for tool in tools {
            summaries.append(await mcpToolSummary(tool, registry: registry, serverID: id))
        }
        return MCPServerToolsResponse(
            serverID: id,
            tools: summaries.sorted { $0.name < $1.name }
        )
    }

    // MARK: - private

    private static func transportLabel(_ transport: MCPTransportConfiguration) -> String {
        SwooshDaemon.mcpTransportLabel(transport)
    }

    private static func makeTransport(_ request: MCPServerCreateRequest) throws -> MCPTransportConfiguration {
        switch request.transport {
        case "stdio":
            guard let command = request.command, !command.isEmpty else {
                throw APIError.badRequest("stdio transport requires a command")
            }
            return .stdio(MCPStdioConfiguration(
                command: command,
                arguments: request.arguments ?? [],
                workingDirectory: request.workingDirectory
            ))
        case "http":
            guard let baseURL = request.baseURL, !baseURL.isEmpty else {
                throw APIError.badRequest("http transport requires baseURL")
            }
            return .http(MCPHTTPConfiguration(baseURL: baseURL))
        default:
            throw APIError.badRequest("unknown transport: \(request.transport)")
        }
    }

    private static func parseTrust(_ raw: String?) throws -> MCPTrustLevel {
        // Empty/missing → safe default. A non-empty unrecognized value is
        // a typo and must NOT silently downgrade to .untrusted.
        guard let raw, !raw.isEmpty else { return .untrusted }
        guard let trust = MCPTrustLevel(rawValue: raw) else {
            throw APIError.badRequest("unknown trustLevel: \(raw)")
        }
        return trust
    }
}
