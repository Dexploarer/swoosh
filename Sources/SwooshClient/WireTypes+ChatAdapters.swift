// SwooshClient/WireTypes+ChatAdapters.swift — 0.4A Chat adapter + Codex auth wire types
//
// Covers `GET /api/chat-adapters`, the toggle endpoint, and the
// `/api/codex/auth/*` state machine. The Codex OAuth status is returned
// by every call in the start/status/cancel triple so the iOS app can
// drive the login flow with one shape.

import Foundation

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

/// Status of an in-flight `codex login` attempt. Returned by
/// `POST /api/codex/auth/start` and `GET /api/codex/auth/status`.
public struct CodexAuthStatus: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case idle
        case pending
        case signedIn = "signed_in"
        case failed
        case cancelled
    }
    public let state: State
    public let message: String?
    public let startedAt: Date?
    /// OAuth URL codex printed when the login process started. Useful
    /// when the daemon and browser live on different machines.
    public let url: String?

    public init(state: State, message: String? = nil,
                startedAt: Date? = nil, url: String? = nil) {
        self.state = state
        self.message = message
        self.startedAt = startedAt
        self.url = url
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
