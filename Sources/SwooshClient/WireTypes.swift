// SwooshClient/WireTypes.swift — 0.4B Core wire format shared by iOS and swooshd
//
// These Codable types are the contract between any Swoosh client and the
// SwooshAPI server. SwooshClient stays transport-agnostic (no Hummingbird
// dependency); SwooshAPI adds the ResponseEncodable conformance on the
// server side. This file holds the always-loaded core types — chat,
// transcript, readiness, error envelopes, version, agent status. Every
// other API tier lives in its own `WireTypes+<Domain>.swift` to honour
// the 400-LOC ceiling.

import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - Chat
// ────────────────────────────────────────────────────────────────────

/// Request body for `POST /api/agent/chat`.
public struct ChatRequest: Codable, Sendable {
    public let sessionID: String
    public let input: String
    public let model: String?
    public let providerID: String?
    /// Wallet address of the calling user. Threaded into `ToolContext`
    /// for stake gating and receipt tracking on crypto toolsets.
    public let walletAddress: String?

    public init(
        sessionID: String = "default",
        input: String,
        model: String? = nil,
        providerID: String? = nil,
        walletAddress: String? = nil
    ) {
        self.sessionID = sessionID
        self.input = input
        self.model = model
        self.providerID = providerID
        self.walletAddress = walletAddress
    }
}

/// Response body for `POST /api/agent/chat`. Mirrors `SwooshCore.AgentResponse`
/// without depending on it — the server translates between the two.
public struct ChatResponse: Codable, Sendable {
    public let message: String
    public let sessionID: String
    public let memoryIDsUsed: [String]
    public let modelUsed: String
    public let createdAt: Date

    public init(
        message: String,
        sessionID: String,
        memoryIDsUsed: [String] = [],
        modelUsed: String = "unknown",
        createdAt: Date = Date()
    ) {
        self.message = message
        self.sessionID = sessionID
        self.memoryIDsUsed = memoryIDsUsed
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Transcript
// ────────────────────────────────────────────────────────────────────

public enum TranscriptRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct TranscriptMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let role: TranscriptRole
    public let content: String
    public let createdAt: Date

    public init(id: String, role: TranscriptRole, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct TranscriptResponse: Codable, Sendable, Equatable {
    public let sessionID: String
    public let messages: [TranscriptMessage]

    public init(sessionID: String, messages: [TranscriptMessage]) {
        self.sessionID = sessionID
        self.messages = messages
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Readiness
// ────────────────────────────────────────────────────────────────────

public enum SwooshReadinessState: String, Codable, Sendable {
    case ready
    case degraded
    case blocked
}

public enum SwooshReadinessStatus: String, Codable, Sendable {
    case ready
    case warning
    case blocked
}

public struct SwooshReadinessComponent: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let status: SwooshReadinessStatus
    public let detail: String
    public let fixCommand: String?

    public init(
        id: String,
        title: String,
        status: SwooshReadinessStatus,
        detail: String,
        fixCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.fixCommand = fixCommand
    }
}

public struct SwooshReadinessReport: Codable, Sendable, Equatable {
    public let state: SwooshReadinessState
    public let summary: String
    public let components: [SwooshReadinessComponent]
    public let generatedAt: Date

    public init(
        state: SwooshReadinessState,
        summary: String,
        components: [SwooshReadinessComponent],
        generatedAt: Date = Date()
    ) {
        self.state = state
        self.summary = summary
        self.components = components
        self.generatedAt = generatedAt
    }

    public var isReady: Bool {
        state == .ready
    }

    public func component(id: String) -> SwooshReadinessComponent? {
        components.first { $0.id == id }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Error envelope, version, agent status
// ────────────────────────────────────────────────────────────────────

/// Generic error envelope returned by the server for non-2xx responses.
public struct APIErrorBody: Codable, Sendable {
    public let error: String
    public let code: String?

    public init(error: String, code: String? = nil) {
        self.error = error
        self.code = code
    }
}

/// Version payload returned by `GET /api/version`.
public struct APIVersion: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct AgentStatusResponse: Codable, Sendable {
    public let status: String
    public let chat: Bool
    public let model: String?
    public let provider: String?
    public let startedAt: Date
    public let chatTurns: Int
    public let lastChatAt: Date?

    public init(
        status: String,
        chat: Bool,
        model: String?,
        provider: String?,
        startedAt: Date,
        chatTurns: Int,
        lastChatAt: Date?
    ) {
        self.status = status
        self.chat = chat
        self.model = model
        self.provider = provider
        self.startedAt = startedAt
        self.chatTurns = chatTurns
        self.lastChatAt = lastChatAt
    }
}
