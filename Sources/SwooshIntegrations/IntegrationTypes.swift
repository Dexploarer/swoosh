// SwooshIntegrations/IntegrationTypes.swift — 0.8B Integration Profiles + Health
//
// Integration profiles, health monitoring, capability snapshots, diffs.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Integration profile
// ═══════════════════════════════════════════════════════════════════

public struct IntegrationProfile: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var kind: IntegrationKind
    public var serverID: String?
    public var pluginID: String?
    public var authStatus: IntegrationAuthStatus
    public var health: IntegrationHealthStatus
    public var risk: RemoteIntegrationRisk
    public var enabled: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, name: String, kind: IntegrationKind,
                serverID: String? = nil, pluginID: String? = nil,
                authStatus: IntegrationAuthStatus = .notConfigured,
                health: IntegrationHealthStatus = .unknown,
                risk: RemoteIntegrationRisk = .medium,
                enabled: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.kind = kind
        self.serverID = serverID; self.pluginID = pluginID
        self.authStatus = authStatus; self.health = health; self.risk = risk
        self.enabled = enabled; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum IntegrationKind: String, Codable, Sendable {
    case remoteMCP, localMCP, plugin, oauthConnector
}

public enum IntegrationAuthStatus: String, Codable, Sendable {
    case notRequired, notConfigured, authorizationRequired
    case authorized, tokenExpired, revoked, failed
}

public enum IntegrationHealthStatus: String, Codable, Sendable {
    case unknown, healthy, degraded, unhealthy, disabled
}

public enum RemoteIntegrationRisk: String, Codable, Sendable {
    case low, medium, high, critical
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Integration health
// ═══════════════════════════════════════════════════════════════════

public struct IntegrationHealth: Codable, Sendable {
    public let integrationID: String
    public let status: IntegrationHealthStatus
    public let lastCheckedAt: Date
    public let latencyMs: Int?
    public let errorSummary: String?
    public let authStatus: IntegrationAuthStatus
    public let capabilityDiffID: String?

    public init(integrationID: String, status: IntegrationHealthStatus, lastCheckedAt: Date = Date(),
                latencyMs: Int? = nil, errorSummary: String? = nil,
                authStatus: IntegrationAuthStatus = .authorized, capabilityDiffID: String? = nil) {
        self.integrationID = integrationID; self.status = status
        self.lastCheckedAt = lastCheckedAt; self.latencyMs = latencyMs
        self.errorSummary = errorSummary; self.authStatus = authStatus
        self.capabilityDiffID = capabilityDiffID
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Capability snapshot
// ═══════════════════════════════════════════════════════════════════

public struct IntegrationCapabilitySnapshot: Codable, Sendable, Identifiable {
    public let id: String
    public let serverID: String
    public let toolNames: [String]
    public let resourceURIs: [String]
    public let promptNames: [String]
    public let capturedAt: Date

    public init(id: String = UUID().uuidString, serverID: String,
                toolNames: [String], resourceURIs: [String] = [],
                promptNames: [String] = [], capturedAt: Date = Date()) {
        self.id = id; self.serverID = serverID; self.toolNames = toolNames
        self.resourceURIs = resourceURIs; self.promptNames = promptNames
        self.capturedAt = capturedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Capability diff
// ═══════════════════════════════════════════════════════════════════

public struct IntegrationCapabilityDiff: Codable, Sendable {
    public let serverID: String
    public let oldSnapshotID: String?
    public let newSnapshotID: String
    public let addedTools: [String]
    public let removedTools: [String]
    public let addedResources: [String]
    public let removedResources: [String]
    public let addedPrompts: [String]
    public let removedPrompts: [String]
    public let requiresUserReview: Bool

    public init(serverID: String, oldSnapshotID: String?, newSnapshotID: String,
                addedTools: [String], removedTools: [String],
                addedResources: [String] = [], removedResources: [String] = [],
                addedPrompts: [String] = [], removedPrompts: [String] = [],
                requiresUserReview: Bool = true) {
        self.serverID = serverID; self.oldSnapshotID = oldSnapshotID
        self.newSnapshotID = newSnapshotID
        self.addedTools = addedTools; self.removedTools = removedTools
        self.addedResources = addedResources; self.removedResources = removedResources
        self.addedPrompts = addedPrompts; self.removedPrompts = removedPrompts
        self.requiresUserReview = requiresUserReview
    }

    public var hasChanges: Bool {
        !addedTools.isEmpty || !removedTools.isEmpty ||
        !addedResources.isEmpty || !removedResources.isEmpty ||
        !addedPrompts.isEmpty || !removedPrompts.isEmpty
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Capability differ
// ═══════════════════════════════════════════════════════════════════

public struct CapabilityDiffer: Sendable {
    public init() {}

    public func diff(old: IntegrationCapabilitySnapshot?, new: IntegrationCapabilitySnapshot) -> IntegrationCapabilityDiff {
        let oldTools = Set(old?.toolNames ?? [])
        let newTools = Set(new.toolNames)
        let oldRes = Set(old?.resourceURIs ?? [])
        let newRes = Set(new.resourceURIs)
        let oldPrompts = Set(old?.promptNames ?? [])
        let newPrompts = Set(new.promptNames)

        let added = newTools.subtracting(oldTools).sorted()
        let removed = oldTools.subtracting(newTools).sorted()
        let addedRes = newRes.subtracting(oldRes).sorted()
        let removedRes = oldRes.subtracting(newRes).sorted()
        let addedP = newPrompts.subtracting(oldPrompts).sorted()
        let removedP = oldPrompts.subtracting(newPrompts).sorted()

        return IntegrationCapabilityDiff(
            serverID: new.serverID, oldSnapshotID: old?.id, newSnapshotID: new.id,
            addedTools: added, removedTools: removed,
            addedResources: addedRes, removedResources: removedRes,
            addedPrompts: addedP, removedPrompts: removedP,
            requiresUserReview: !added.isEmpty || !removed.isEmpty
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Integration registry
// ═══════════════════════════════════════════════════════════════════

public actor IntegrationRegistry {
    private var profiles: [String: IntegrationProfile] = [:]
    private var snapshots: [String: IntegrationCapabilitySnapshot] = [:]
    private var healthRecords: [String: IntegrationHealth] = [:]
    private var auditLog: [IntegrationAuditEvent] = []

    public init() {}

    // ── Profile CRUD ──────────────────────────────────────────────

    public func addProfile(_ profile: IntegrationProfile) {
        profiles[profile.id] = profile
        appendAudit(.init(kind: .profileCreated, integrationID: profile.id, message: "Integration created: \(profile.name)"))
    }

    public func getProfile(_ id: String) -> IntegrationProfile? { profiles[id] }

    public func listProfiles() -> [IntegrationProfile] {
        Array(profiles.values).sorted { $0.name < $1.name }
    }

    public func updateProfile(_ profile: IntegrationProfile) {
        profiles[profile.id] = profile
    }

    // ── Snapshots ─────────────────────────────────────────────────

    public func saveSnapshot(_ snapshot: IntegrationCapabilitySnapshot) {
        snapshots[snapshot.id] = snapshot
        appendAudit(.init(kind: .snapshotCreated, integrationID: snapshot.serverID, message: "Capability snapshot captured"))
    }

    public func getSnapshot(_ id: String) -> IntegrationCapabilitySnapshot? { snapshots[id] }

    public func latestSnapshot(serverID: String) -> IntegrationCapabilitySnapshot? {
        snapshots.values.filter { $0.serverID == serverID }.sorted { $0.capturedAt > $1.capturedAt }.first
    }

    // ── Health ────────────────────────────────────────────────────

    public func recordHealth(_ health: IntegrationHealth) {
        healthRecords[health.integrationID] = health
        if health.status == .degraded || health.status == .unhealthy {
            appendAudit(.init(kind: .healthDegraded, integrationID: health.integrationID, message: "Health: \(health.status.rawValue)"))
        }
    }

    public func getHealth(_ integrationID: String) -> IntegrationHealth? { healthRecords[integrationID] }

    // ── Audit ─────────────────────────────────────────────────────

    private func appendAudit(_ event: IntegrationAuditEvent) { auditLog.append(event) }
    public func getAuditLog() -> [IntegrationAuditEvent] { auditLog }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Integration audit
// ═══════════════════════════════════════════════════════════════════

public struct IntegrationAuditEvent: Codable, Sendable {
    public let kind: IntegrationAuditKind
    public let integrationID: String
    public let message: String
    public let createdAt: Date

    public init(kind: IntegrationAuditKind, integrationID: String, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.integrationID = integrationID
        self.message = message; self.createdAt = createdAt
    }
}

public enum IntegrationAuditKind: String, Codable, Sendable {
    case profileCreated, profileEnabled, profileDisabled
    case snapshotCreated, capabilityDriftDetected
    case capabilityChangeApproved, capabilityChangeRejected
    case healthChecked, healthDegraded, healthRestored
    case profileExported, profileImported
}
