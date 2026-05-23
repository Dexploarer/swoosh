// SwooshClient/WireTypes+Providers.swift — 0.4A Provider/auth wire types
//
// Split from WireTypes.swift to honour the 400-LOC ceiling. Carries the
// provider summary plus auth/selection request and response envelopes
// used by `GET /api/providers`, `POST /api/providers/auth`, etc.

import Foundation

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

public struct ProviderAuthRequest: Codable, Sendable {
    public let providerID: String
    public let apiKey: String

    public init(providerID: String, apiKey: String) {
        self.providerID = providerID
        self.apiKey = apiKey
    }
}

public struct ProviderSelectionRequest: Codable, Sendable {
    public let providerID: String

    public init(providerID: String) {
        self.providerID = providerID
    }
}

public struct ProviderMutationResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let activeProviderID: String?
    public let preferredProviderID: String?
    public let requiresRestart: Bool
    public let message: String

    public init(
        providers: [ProviderSummary],
        activeProviderID: String?,
        preferredProviderID: String?,
        requiresRestart: Bool,
        message: String
    ) {
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.preferredProviderID = preferredProviderID
        self.requiresRestart = requiresRestart
        self.message = message
    }
}

public struct ProvidersResponse: Codable, Sendable {
    public let providers: [ProviderSummary]
    public let activeProviderID: String?
    public let preferredProviderID: String?

    public init(providers: [ProviderSummary], activeProviderID: String?, preferredProviderID: String? = nil) {
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.preferredProviderID = preferredProviderID
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
