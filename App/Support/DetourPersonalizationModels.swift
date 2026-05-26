// DetourPersonalizationModels.swift — personalization setup model types (0.5A)

import AppKit
#if canImport(Contacts)
import Contacts
#endif
import Foundation
import OSLog
#if canImport(Security)
import Security
#endif

struct DetourPersonalizationProgress: Codable, Equatable {
    var fraction: Double
    var title: String
    var tip: String

    static let idle = DetourPersonalizationProgress(
        fraction: 0,
        title: "Ready",
        tip: "Your context stays on this Mac."
    )

    static let complete = DetourPersonalizationProgress(
        fraction: 1,
        title: "Ready",
        tip: "Setup recommendations are ready."
    )
}

enum DetourSetupCategory: String, Codable, Equatable {
    case connector
    case account
    case permission
    case goal
    case schedule
    case model
    case identity
    case context
    case skill
    case mcp
}

struct DetourSetupCandidate: Codable, Equatable {
    var id: String
    var category: DetourSetupCategory
    var title: String
    var detail: String
    var source: String
    var recommended: Bool
    var selected: Bool
    var prompt: String?
    var foundCount: Int?
    var credentialProviderID: String?
    var credentialKeys: [String]?
    var scope: DetourDelegationRole?
}

enum DetourSetupApplicationState: String, Codable, Equatable {
    case checking
    case connected
    case enabled
    case needsAction
    case removed
    case failed
}

struct DetourSetupApplicationItem: Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var state: DetourSetupApplicationState
    var doctor: String? = nil
}

struct DetourSetupApplicationReport: Codable, Equatable {
    var items: [DetourSetupApplicationItem]
    var savedAt: Date
}

struct DetourPersonalizationCalibrationAnswer: Codable, Equatable {
    var id: String
    var question: String
    var answer: String
}

struct DetourRelationshipGuidance: Codable, Equatable {
    var relationshipID: String
    var displayName: String
    var source: String
    var tags: [String]
    var messageCount: Int?
    var lastSeenDescription: String?
    var guidance: String
}

struct DetourPersonalizationEventRoute: Codable, Equatable {
    var event: String
    var contextVariable: String
    var templateTag: String
    var policy: String
}

struct DetourPersonalizationTemplateSet: Codable, Equatable {
    var shouldRespondTemplate: String
    var messageHandlerTemplate: String
    var reflectionTemplate: String
    var machineEventTemplate: String
}

struct DetourPersonalizationCalibration: Codable, Equatable {
    var schemaVersion: Int
    var userName: String
    var agentName: String
    var answers: [DetourPersonalizationCalibrationAnswer]
    var selectedSetup: [DetourSetupCandidate]
    var setupCandidateScopes: [String: String]
    var delegationProfiles: [DetourDelegationProfile]
    var relationshipGuidance: [DetourRelationshipGuidance]
    var eventRoutes: [DetourPersonalizationEventRoute]
    var templates: DetourPersonalizationTemplateSet
    var savedAt: Date
}

struct DetourRelationshipCandidate: Codable, Equatable {
    var id: String
    var displayName: String
    var source: String
    var tags: [String]
    var messageCount: Int?
    var lastSeenDescription: String?
    var selected: Bool
}

struct DetourPersonalizationScanResult: Codable, Equatable {
    var summary: String
    var signals: [String]
    var accessItems: [String]
    var accounts: [String]
    var goals: [String]
    var schedules: [String]
    var plugins: [String]
    var questions: [String]
    var setupCandidates: [DetourSetupCandidate]
    var relationshipCandidates: [DetourRelationshipCandidate]
    var delegationProfiles: [DetourDelegationProfile]
    var completedAt: Date
    var scoutSucceeded: Bool
    var agentContextSucceeded: Bool
    var credentialInheritanceSucceeded: Bool
}

enum DetourPersonalizationError: Error {
    case commandFailed(Int32)
}

struct DetourSetupVerificationError: LocalizedError {
    var errorDescription: String?
}

struct DetourCredentialApplyResult {
    var requestedProviderIDs: Set<String>
    var verifiedProviderIDs: Set<String>
    var requestedKeys: Set<String>
    var importedLegacyKeys: Set<String>
    var availableLegacyKeys: Set<String>
}

struct AppInventory {
    var names: Set<String>
    var displayNames: [String]
}

struct DetourPersonalizationAppliedSetup: Codable {
    var approvedCandidateIDs: [String]
    var deniedCandidateIDs: [String]
    var approvedCandidates: [DetourSetupCandidate]
    var setupCandidateScopes: [String: String]
    var relationships: [DetourRelationshipCandidate]
    var delegationProfiles: [DetourDelegationProfile]
    var savedAt: Date
}

struct ConnectorPluginSpec {
    var candidateID: String
    var pluginID: String
    var displayName: String
    var requiredCredentialKeys: [String]
    var toolNameFragments: [String]
}

struct DetourMCPServerSpec {
    var candidateID: String
    var serverID: String
    var displayName: String
    var detail: String
    var transport: String = "stdio"
    var command: String? = nil
    var arguments: [String] = []
    var workingDirectory: String? = nil
    var environmentSecretRefs: [String: String]
    var baseURL: String? = nil
    var authorizationSecretRef: String? = nil
    var localOnly: Bool? = nil
    var requiredCredentialKeys: [String]
    var missingCredentialDescription: String
}

struct DetourMCPServerProfile: Codable {
    var id: String
    var name: String
    var description: String?
    var transport: DetourMCPTransportConfiguration
    var state: String
    var trustLevel: String
    var enabled: Bool
    var toolPolicy: DetourMCPToolPolicy
    var resourcePolicy: DetourMCPResourcePolicy
    var promptPolicy: DetourMCPPromptPolicy
    var createdAt: Date
    var updatedAt: Date
}

struct DetourMCPServerCreateRequest: Encodable {
    var id: String
    var name: String
    var description: String?
    var transport: String
    var command: String?
    var arguments: [String]?
    var workingDirectory: String?
    var environmentSecretRefs: [String: String]?
    var baseURL: String?
    var authorizationSecretRef: String?
    var localOnly: Bool?
    var trustLevel: String?
    var enabled: Bool?
}

enum DetourMCPTransportConfiguration: Codable {
    case stdio(DetourMCPStdioConfiguration)
    case http(DetourMCPHTTPConfiguration)
}

struct DetourMCPStdioConfiguration: Codable {
    var command: String
    var arguments: [String]
    var workingDirectory: String?
    var environmentSecretRefs: [String: String]
}

struct DetourMCPHTTPConfiguration: Codable {
    var baseURL: String
    var authorizationSecretRef: String?
    var localOnly: Bool
}

struct DetourMCPToolPolicy: Codable {
    var importTools: Bool
    var defaultRisk: String
    var allowlist: [String]
    var denylist: [String]
    var maxResultBytes: Int
    var requireUserApprovalForAllCalls: Bool

    static let safeDefault = DetourMCPToolPolicy(
        importTools: true,
        defaultRisk: "medium",
        allowlist: [],
        denylist: [],
        maxResultBytes: 64_000,
        requireUserApprovalForAllCalls: true
    )
}

struct DetourMCPResourcePolicy: Codable {
    var importResources: Bool
    var allowResourceReads: Bool
    var maxResourceBytes: Int
    var requireApprovalForResourceRead: Bool
    var denyURIPatterns: [String]

    static let safeDefault = DetourMCPResourcePolicy(
        importResources: true,
        allowResourceReads: true,
        maxResourceBytes: 256_000,
        requireApprovalForResourceRead: true,
        denyURIPatterns: ["*cookie*", "*secret*", "*private_key*", "*.env*"]
    )
}

struct DetourMCPPromptPolicy: Codable {
    var importPrompts: Bool
    var allowPromptUse: Bool
    var requireUserSelection: Bool
    var requirePreviewBeforeUse: Bool

    static let safeDefault = DetourMCPPromptPolicy(
        importPrompts: true,
        allowPromptUse: true,
        requireUserSelection: true,
        requirePreviewBeforeUse: true
    )
}
