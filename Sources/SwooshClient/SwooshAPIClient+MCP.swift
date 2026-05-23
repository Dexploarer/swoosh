// SwooshClient/SwooshAPIClient+MCP.swift — 0.4A MCP server CRUD endpoints
//
// Wire methods for `POST /api/mcp/servers`, `DELETE
// /api/mcp/servers/{id}`, the connect / disconnect mutations, and the
// per-server tool discovery endpoint. `GET /api/mcp/servers` (list) is
// on the core client.

import Foundation

extension SwooshAPIClient {
    public func addMCPServer(_ body: MCPServerCreateRequest) async throws -> MCPServerMutationResponse {
        let encoded = try encoder.encode(body)
        let request = try makeRequest(method: "POST", path: "api/mcp/servers", body: encoded)
        return try await execute(request, as: MCPServerMutationResponse.self)
    }

    public func removeMCPServer(id: String) async throws -> MCPServersResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "DELETE", path: "api/mcp/servers/\(encodedID)", body: nil)
        return try await execute(request, as: MCPServersResponse.self)
    }

    public func connectMCPServer(id: String) async throws -> MCPServerMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/mcp/servers/\(encodedID)/connect", body: nil)
        return try await execute(request, as: MCPServerMutationResponse.self)
    }

    public func disconnectMCPServer(id: String) async throws -> MCPServerMutationResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "POST", path: "api/mcp/servers/\(encodedID)/disconnect", body: nil)
        return try await execute(request, as: MCPServerMutationResponse.self)
    }

    public func mcpServerTools(id: String) async throws -> MCPServerToolsResponse {
        let encodedID = try pathComponent(id)
        let request = try makeRequest(method: "GET", path: "api/mcp/servers/\(encodedID)/tools", body: nil)
        return try await execute(request, as: MCPServerToolsResponse.self)
    }
}
