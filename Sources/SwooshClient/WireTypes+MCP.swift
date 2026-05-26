// SwooshClient/WireTypes+MCP.swift — 0.4A MCP server runtime + CRUD wire types
//
// Wire format for `GET /api/mcp/servers`, `POST /api/mcp/servers`, and
// the connect/disconnect/tools endpoints. MCP servers are added at the
// daemon and proxied as ordinary tools via `MCPBridgePluginExecutor`.

import Foundation

public struct MCPDiscoveredToolSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let title: String?
    public let description: String?
    public let estimatedRisk: String

    public init(id: String, name: String, title: String?, description: String?, estimatedRisk: String) {
        self.id = id
        self.name = name
        self.title = title
        self.description = description
        self.estimatedRisk = estimatedRisk
    }
}

public struct MCPServerRuntimeSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let enabled: Bool
    public let trustLevel: String
    public let state: String
    public let transport: String
    public let toolCount: Int
    public let importedToolCount: Int
    public let tools: [MCPDiscoveredToolSummary]

    public init(
        id: String,
        name: String,
        description: String?,
        enabled: Bool,
        trustLevel: String,
        state: String,
        transport: String,
        toolCount: Int,
        importedToolCount: Int,
        tools: [MCPDiscoveredToolSummary]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.trustLevel = trustLevel
        self.state = state
        self.transport = transport
        self.toolCount = toolCount
        self.importedToolCount = importedToolCount
        self.tools = tools
    }
}

public struct MCPServersResponse: Codable, Sendable, Equatable {
    public let servers: [MCPServerRuntimeSummary]
    public let generatedAt: Date

    public init(servers: [MCPServerRuntimeSummary], generatedAt: Date = Date()) {
        self.servers = servers
        self.generatedAt = generatedAt
    }
}

public struct MCPServerCreateRequest: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let transport: String          // "stdio" | "http"
    public let command: String?           // stdio
    public let arguments: [String]?
    public let workingDirectory: String?
    public let environmentSecretRefs: [String: String]?
    public let baseURL: String?           // http
    public let authorizationSecretRef: String?
    public let localOnly: Bool?
    public let trustLevel: String?
    public let enabled: Bool?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        transport: String,
        command: String? = nil,
        arguments: [String]? = nil,
        workingDirectory: String? = nil,
        environmentSecretRefs: [String: String]? = nil,
        baseURL: String? = nil,
        authorizationSecretRef: String? = nil,
        localOnly: Bool? = nil,
        trustLevel: String? = nil,
        enabled: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentSecretRefs = environmentSecretRefs
        self.baseURL = baseURL
        self.authorizationSecretRef = authorizationSecretRef
        self.localOnly = localOnly
        self.trustLevel = trustLevel
        self.enabled = enabled
    }
}

public struct MCPServerMutationResponse: Codable, Sendable, Equatable {
    public let server: MCPServerRuntimeSummary
    public let message: String

    public init(server: MCPServerRuntimeSummary, message: String) {
        self.server = server
        self.message = message
    }
}

public struct MCPServerToolsResponse: Codable, Sendable, Equatable {
    public let serverID: String
    public let tools: [MCPDiscoveredToolSummary]

    public init(serverID: String, tools: [MCPDiscoveredToolSummary]) {
        self.serverID = serverID
        self.tools = tools
    }
}
