// SwooshFlow/SessionTrace.swift — Trace extraction for /repeat (0.5A)

import Foundation
import SwooshTools

// MARK: - Session trace

public struct SessionTrace: Codable, Sendable {
    public let sessionID: String
    public let userMessages: [TraceMessage]
    public let assistantMessages: [TraceMessage]
    public let toolCalls: [ToolCallTrace]
    public let approvalIDs: [String]
    public let memoryIDsUsed: [String]
    public let setupReportID: String?
    public let createdAt: Date

    public init(
        sessionID: String, userMessages: [TraceMessage] = [],
        assistantMessages: [TraceMessage] = [], toolCalls: [ToolCallTrace] = [],
        approvalIDs: [String] = [], memoryIDsUsed: [String] = [],
        setupReportID: String? = nil, createdAt: Date = Date()
    ) {
        self.sessionID = sessionID; self.userMessages = userMessages
        self.assistantMessages = assistantMessages; self.toolCalls = toolCalls
        self.approvalIDs = approvalIDs; self.memoryIDsUsed = memoryIDsUsed
        self.setupReportID = setupReportID; self.createdAt = createdAt
    }
}

public struct TraceMessage: Codable, Sendable {
    public let id: String
    public let content: String
    public let timestamp: Date

    public init(id: String, content: String, timestamp: Date = Date()) {
        self.id = id; self.content = content; self.timestamp = timestamp
    }
}

// MARK: - Trace scope

public enum WorkflowTraceScope: Codable, Sendable {
    case latestAssistantResponse
    case entireSession
    case sinceMessage(messageID: String)
    case selectedMessages([String])
}

// MARK: - Trace extractor protocol

public protocol WorkflowTraceExtracting: Sendable {
    func extractTrace(sessionID: String, scope: WorkflowTraceScope) async throws -> SessionTrace
}

// MARK: - Default extractor

/// Extracts session traces from stored transcripts and tool traces.
public struct DefaultWorkflowTraceExtractor: WorkflowTraceExtracting, Sendable {
    private let sessionLoader: any SessionTraceLoading

    public init(sessionLoader: any SessionTraceLoading) {
        self.sessionLoader = sessionLoader
    }

    public func extractTrace(sessionID: String, scope: WorkflowTraceScope) async throws -> SessionTrace {
        let raw = try await sessionLoader.loadSessionTrace(sessionID: sessionID)

        switch scope {
        case .latestAssistantResponse:
            // Include only tool calls from the latest model turn
            let lastToolCalls = raw.toolCalls.isEmpty ? [] : [raw.toolCalls.last!]
            return SessionTrace(
                sessionID: sessionID,
                userMessages: raw.userMessages.suffix(1).map { $0 },
                assistantMessages: raw.assistantMessages.suffix(1).map { $0 },
                toolCalls: lastToolCalls,
                approvalIDs: raw.approvalIDs,
                memoryIDsUsed: raw.memoryIDsUsed,
                createdAt: raw.createdAt
            )
        case .entireSession:
            return raw
        case .sinceMessage(let messageID):
            guard let idx = raw.userMessages.firstIndex(where: { $0.id == messageID }) else {
                return raw
            }
            return SessionTrace(
                sessionID: sessionID,
                userMessages: Array(raw.userMessages[idx...]),
                assistantMessages: raw.assistantMessages.filter { msg in
                    msg.timestamp >= raw.userMessages[idx].timestamp
                },
                toolCalls: raw.toolCalls.filter { trace in
                    trace.startedAt >= raw.userMessages[idx].timestamp
                },
                approvalIDs: raw.approvalIDs,
                memoryIDsUsed: raw.memoryIDsUsed,
                createdAt: raw.createdAt
            )
        case .selectedMessages(let ids):
            let idSet = Set(ids)
            return SessionTrace(
                sessionID: sessionID,
                userMessages: raw.userMessages.filter { idSet.contains($0.id) },
                assistantMessages: raw.assistantMessages,
                toolCalls: raw.toolCalls,
                approvalIDs: raw.approvalIDs,
                memoryIDsUsed: raw.memoryIDsUsed,
                createdAt: raw.createdAt
            )
        }
    }
}

// MARK: - Session trace loading protocol

public protocol SessionTraceLoading: Sendable {
    func loadSessionTrace(sessionID: String) async throws -> SessionTrace
}
