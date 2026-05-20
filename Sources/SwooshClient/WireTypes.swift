// SwooshClient/WireTypes.swift — Wire format shared by the iOS app and swooshd
//
// These Codable types are the contract between any Swoosh client and the
// SwooshAPI server. SwooshClient stays transport-agnostic (no Hummingbird
// dependency); SwooshAPI adds the ResponseEncodable conformance on the
// server side.

import Foundation

/// Request body for `POST /api/agent/chat`.
public struct ChatRequest: Codable, Sendable {
    public let sessionID: String
    public let input: String

    public init(sessionID: String = "default", input: String) {
        self.sessionID = sessionID
        self.input = input
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

public struct ProviderSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let model: String?
    public let configured: Bool
    public let active: Bool
    public let status: String

    public init(
        id: String,
        name: String,
        model: String?,
        configured: Bool,
        active: Bool,
        status: String
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.configured = configured
        self.active = active
        self.status = status
    }
}

public struct ProvidersResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let activeProviderID: String?

    public init(providers: [ProviderSummary], activeProviderID: String?) {
        self.providers = providers
        self.activeProviderID = activeProviderID
    }
}

public struct ProviderStatusResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let checkedAt: Date

    public init(providers: [ProviderSummary], checkedAt: Date = Date()) {
        self.providers = providers
        self.checkedAt = checkedAt
    }
}

public struct BoardLaneSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let cardCount: Int

    public init(id: String, title: String, cardCount: Int) {
        self.id = id
        self.title = title
        self.cardCount = cardCount
    }
}

public struct BoardCardSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let laneID: String
    public let title: String
    public let detail: String
    public let updatedAt: Date

    public init(id: String, laneID: String, title: String, detail: String, updatedAt: Date = Date()) {
        self.id = id
        self.laneID = laneID
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct BoardLanesResponse: Codable, Sendable {
    public let lanes: [BoardLaneSummary]

    public init(lanes: [BoardLaneSummary]) {
        self.lanes = lanes
    }
}

public struct BoardCardsResponse: Codable, Sendable {
    public let cards: [BoardCardSummary]

    public init(cards: [BoardCardSummary]) {
        self.cards = cards
    }
}

public struct MetricCounter: Codable, Sendable, Identifiable {
    public let id: String
    public let value: Int

    public init(id: String, value: Int) {
        self.id = id
        self.value = value
    }
}

public struct MetricsResponse: Codable, Sendable {
    public let counters: [MetricCounter]
    public let generatedAt: Date

    public init(counters: [MetricCounter], generatedAt: Date = Date()) {
        self.counters = counters
        self.generatedAt = generatedAt
    }
}

public struct UsageResponse: Codable, Sendable {
    public let chatTurns: Int
    public let approvedMemoryReferences: Int
    public let lastChatAt: Date?
    public let generatedAt: Date

    public init(
        chatTurns: Int,
        approvedMemoryReferences: Int,
        lastChatAt: Date?,
        generatedAt: Date = Date()
    ) {
        self.chatTurns = chatTurns
        self.approvedMemoryReferences = approvedMemoryReferences
        self.lastChatAt = lastChatAt
        self.generatedAt = generatedAt
    }
}

public struct SkillSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let trust: String

    public init(id: String, title: String, description: String, category: String, trust: String) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.trust = trust
    }
}

public struct SkillsResponse: Codable, Sendable {
    public let skills: [SkillSummary]

    public init(skills: [SkillSummary]) {
        self.skills = skills
    }
}

public struct ChatAdapterSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let packageName: String?
    public let distribution: String
    public let enabled: Bool
    public let configured: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]
    public let supportsStreaming: Bool
    public let supportsDMs: Bool
    public let supportsCards: Bool
    public let supportsModals: Bool

    public init(
        id: String,
        displayName: String,
        packageName: String?,
        distribution: String = "official",
        enabled: Bool,
        configured: Bool,
        missingCredentials: [String],
        configurationNotes: [String] = [],
        supportsStreaming: Bool,
        supportsDMs: Bool,
        supportsCards: Bool,
        supportsModals: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.packageName = packageName
        self.distribution = distribution
        self.enabled = enabled
        self.configured = configured
        self.missingCredentials = missingCredentials
        self.configurationNotes = configurationNotes
        self.supportsStreaming = supportsStreaming
        self.supportsDMs = supportsDMs
        self.supportsCards = supportsCards
        self.supportsModals = supportsModals
    }
}

public struct ChatStateAdapterSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let packageName: String?
    public let distribution: String
    public let productionReady: Bool
    public let enabled: Bool
    public let configured: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]

    public init(
        id: String,
        displayName: String,
        packageName: String?,
        distribution: String,
        productionReady: Bool,
        enabled: Bool,
        configured: Bool,
        missingCredentials: [String],
        configurationNotes: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.packageName = packageName
        self.distribution = distribution
        self.productionReady = productionReady
        self.enabled = enabled
        self.configured = configured
        self.missingCredentials = missingCredentials
        self.configurationNotes = configurationNotes
    }
}

public struct ChatAdaptersResponse: Codable, Sendable {
    public let adapters: [ChatAdapterSummary]
    public let stateAdapters: [ChatStateAdapterSummary]

    public init(adapters: [ChatAdapterSummary], stateAdapters: [ChatStateAdapterSummary] = []) {
        self.adapters = adapters
        self.stateAdapters = stateAdapters
    }
}

public struct ChatAdapterToggleRequest: Codable, Sendable {
    public let id: String
    public let enabled: Bool

    public init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}
