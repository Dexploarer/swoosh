// SwooshClient/WireTypes+Runtime.swift — 0.4A Runtime config + flag updates
//
// Covers `GET /api/runtime/config`, `POST /api/runtime/flags`,
// `POST /api/runtime/profile`, and the `GET /api/usage` envelope.
// Runtime flags toggle safety knobs at the daemon; the profile is the
// permission preset (e.g. "personal", "balanced", "max").

import Foundation

public struct RuntimeFlagSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let enabled: Bool

    public init(id: String, label: String, enabled: Bool) {
        self.id = id
        self.label = label
        self.enabled = enabled
    }
}

public struct ToolPolicySummary: Codable, Sendable, Equatable {
    public let maxToolCallsPerTurn: Int
    public let maxToolChainDepth: Int
    public let allowModelToolCalls: Bool
    public let allowHumanOnlyFromModel: Bool
    public let allowCriticalToolsFromModel: Bool
    public let requireApprovalForMediumRiskAndAbove: Bool

    public init(
        maxToolCallsPerTurn: Int,
        maxToolChainDepth: Int,
        allowModelToolCalls: Bool,
        allowHumanOnlyFromModel: Bool,
        allowCriticalToolsFromModel: Bool,
        requireApprovalForMediumRiskAndAbove: Bool
    ) {
        self.maxToolCallsPerTurn = maxToolCallsPerTurn
        self.maxToolChainDepth = maxToolChainDepth
        self.allowModelToolCalls = allowModelToolCalls
        self.allowHumanOnlyFromModel = allowHumanOnlyFromModel
        self.allowCriticalToolsFromModel = allowCriticalToolsFromModel
        self.requireApprovalForMediumRiskAndAbove = requireApprovalForMediumRiskAndAbove
    }
}

public struct RuntimeConfigResponse: Codable, Sendable, Equatable {
    public let configured: Bool
    public let setupMode: String?
    public let permissionProfile: String?
    public let modelPath: String?
    public let daemonHost: String?
    public let daemonPort: Int?
    public let preferredProviderID: String?
    public let localDiagnosticFallback: Bool
    public let toolPolicy: ToolPolicySummary?
    public let safetyFlags: [RuntimeFlagSummary]

    public init(
        configured: Bool,
        setupMode: String?,
        permissionProfile: String?,
        modelPath: String?,
        daemonHost: String?,
        daemonPort: Int?,
        preferredProviderID: String? = nil,
        localDiagnosticFallback: Bool,
        toolPolicy: ToolPolicySummary?,
        safetyFlags: [RuntimeFlagSummary]
    ) {
        self.configured = configured
        self.setupMode = setupMode
        self.permissionProfile = permissionProfile
        self.modelPath = modelPath
        self.daemonHost = daemonHost
        self.daemonPort = daemonPort
        self.preferredProviderID = preferredProviderID
        self.localDiagnosticFallback = localDiagnosticFallback
        self.toolPolicy = toolPolicy
        self.safetyFlags = safetyFlags
    }
}

public struct RuntimeFlagUpdate: Codable, Sendable, Equatable {
    public let id: String
    public let enabled: Bool

    public init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}

public struct RuntimeFlagUpdateRequest: Codable, Sendable, Equatable {
    public let flags: [RuntimeFlagUpdate]

    public init(flags: [RuntimeFlagUpdate]) {
        self.flags = flags
    }
}

public struct RuntimeProfileUpdateRequest: Codable, Sendable, Equatable {
    public let permissionProfile: String

    public init(permissionProfile: String) {
        self.permissionProfile = permissionProfile
    }
}

public struct RuntimeConfigMutationResponse: Codable, Sendable, Equatable {
    public let config: RuntimeConfigResponse
    public let requiresRestart: Bool
    public let message: String

    public init(config: RuntimeConfigResponse, requiresRestart: Bool, message: String) {
        self.config = config
        self.requiresRestart = requiresRestart
        self.message = message
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
