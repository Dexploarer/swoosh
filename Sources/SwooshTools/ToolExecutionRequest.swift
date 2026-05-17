// SwooshTools/ToolExecutionRequest.swift — Tool execution request (0.4B)
//
// A validated request to execute a tool. Created by the parser or manually.

import Foundation

public struct ToolExecutionRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let arguments: JSONValue
    public let origin: ToolCallOrigin
    public let sessionID: String
    public let messageID: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        arguments: JSONValue,
        origin: ToolCallOrigin,
        sessionID: String,
        messageID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.origin = origin
        self.sessionID = sessionID
        self.messageID = messageID
        self.createdAt = createdAt
    }
}
