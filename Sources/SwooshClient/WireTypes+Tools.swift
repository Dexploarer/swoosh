// SwooshClient/WireTypes+Tools.swift — 0.4A Tool catalog + execute wire types
//
// Wire format for `GET /api/tools` (catalog projection) and
// `POST /api/tools/{name}/execute`. The execute path goes through the
// firewall + approval queue on the server — the wire never carries a
// permission grant.

import Foundation

public struct ToolCatalogToolSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let permission: String
    public let risk: String
    public let approval: String
    public let toolset: String
    public let platforms: [String]

    public init(
        id: String,
        name: String,
        displayName: String,
        description: String,
        permission: String,
        risk: String,
        approval: String,
        toolset: String,
        platforms: [String]
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.permission = permission
        self.risk = risk
        self.approval = approval
        self.toolset = toolset
        self.platforms = platforms
    }
}

public struct ToolsetSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let toolCount: Int
    public let readOnlyCount: Int
    public let writeCount: Int
    public let humanOnlyCount: Int

    public init(id: String, toolCount: Int, readOnlyCount: Int, writeCount: Int, humanOnlyCount: Int) {
        self.id = id
        self.toolCount = toolCount
        self.readOnlyCount = readOnlyCount
        self.writeCount = writeCount
        self.humanOnlyCount = humanOnlyCount
    }
}

public struct ToolCatalogResponse: Codable, Sendable, Equatable {
    public let tools: [ToolCatalogToolSummary]
    public let toolsets: [ToolsetSummary]
    public let generatedAt: Date

    public init(tools: [ToolCatalogToolSummary], toolsets: [ToolsetSummary], generatedAt: Date = Date()) {
        self.tools = tools
        self.toolsets = toolsets
        self.generatedAt = generatedAt
    }
}

public struct ToolExecuteRequest: Codable, Sendable, Equatable {
    public let argsJSON: String
    public let sessionID: String?

    public init(argsJSON: String = "{}", sessionID: String? = nil) {
        self.argsJSON = argsJSON
        self.sessionID = sessionID
    }
}

public struct ToolExecuteResponse: Codable, Sendable, Equatable {
    public let toolName: String
    public let success: Bool
    public let outputJSON: String?
    public let error: String?
    public let durationMs: Int

    public init(
        toolName: String,
        success: Bool,
        outputJSON: String?,
        error: String?,
        durationMs: Int
    ) {
        self.toolName = toolName
        self.success = success
        self.outputJSON = outputJSON
        self.error = error
        self.durationMs = durationMs
    }
}
