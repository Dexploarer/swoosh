// SwooshSetup/SetupTypes.swift — 0.9A Native App Polish + Private Alpha
//
// Setup wizard, profiles, steps, first-run state, import wizard.
// No cookie ingestion. No raw secrets. No full-disk scan.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Setup profile
// ═══════════════════════════════════════════════════════════════════

public enum SetupProfile: String, Codable, Sendable, CaseIterable {
    case quick, developer, full, importExisting, headless
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Setup step protocol
// ═══════════════════════════════════════════════════════════════════

public protocol SetupStep: Sendable {
    var id: String { get }
    var title: String { get }
    var description: String { get }
    var dependencies: [String] { get }

    func detect(context: SetupContext) async throws -> SetupStepStatus
    func configure(context: SetupContext) async throws -> SetupStepResult
    func verify(context: SetupContext) async throws -> SetupVerificationResult
    func rollback(context: SetupContext) async throws
}

public struct SetupContext: Sendable {
    public let profile: SetupProfile
    public let configPath: String
    public let statePath: String
    public let approvedRoots: [String]
    public let dryRun: Bool

    public init(profile: SetupProfile, configPath: String = "~/.swoosh/config.yaml",
                statePath: String = "~/Library/Application Support/Swoosh/state",
                approvedRoots: [String] = [], dryRun: Bool = false) {
        self.profile = profile; self.configPath = configPath
        self.statePath = statePath; self.approvedRoots = approvedRoots
        self.dryRun = dryRun
    }
}

public enum SetupStepStatus: String, Codable, Sendable {
    case notStarted, ready, configured, verified, failed, skipped
}

public struct SetupStepResult: Codable, Sendable {
    public let stepID: String
    public let status: SetupStepStatus
    public let message: String?
    public let createdAt: Date

    public init(stepID: String, status: SetupStepStatus, message: String? = nil, createdAt: Date = Date()) {
        self.stepID = stepID; self.status = status; self.message = message; self.createdAt = createdAt
    }
}

public struct SetupVerificationResult: Codable, Sendable {
    public let stepID: String
    public let passed: Bool
    public let message: String?

    public init(stepID: String, passed: Bool, message: String? = nil) {
        self.stepID = stepID; self.passed = passed; self.message = message
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - First-run state
// ═══════════════════════════════════════════════════════════════════

public struct FirstRunState: Codable, Sendable {
    public var setupCompleted: Bool
    public var profile: SetupProfile?
    public var completedStepIDs: [String]
    public var failedStepIDs: [String]
    public var startedAt: Date?
    public var completedAt: Date?

    public static let initial = FirstRunState(
        setupCompleted: false, profile: nil,
        completedStepIDs: [], failedStepIDs: []
    )

    public init(setupCompleted: Bool, profile: SetupProfile?,
                completedStepIDs: [String], failedStepIDs: [String],
                startedAt: Date? = nil, completedAt: Date? = nil) {
        self.setupCompleted = setupCompleted; self.profile = profile
        self.completedStepIDs = completedStepIDs; self.failedStepIDs = failedStepIDs
        self.startedAt = startedAt; self.completedAt = completedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Setup report
// ═══════════════════════════════════════════════════════════════════

public struct SetupReport: Codable, Sendable {
    public let id: String
    public let profile: SetupProfile
    public let steps: [SetupStepResult]
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let createdAt: Date

    public init(id: String = UUID().uuidString, profile: SetupProfile,
                steps: [SetupStepResult], createdAt: Date = Date()) {
        self.id = id; self.profile = profile; self.steps = steps
        self.passed = steps.filter { $0.status == .verified || $0.status == .configured }.count
        self.failed = steps.filter { $0.status == .failed }.count
        self.skipped = steps.filter { $0.status == .skipped }.count
        self.createdAt = createdAt
    }

    public var isComplete: Bool { failed == 0 }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Permission profile
// ═══════════════════════════════════════════════════════════════════

public enum PermissionProfile: String, Codable, Sendable, CaseIterable {
    case safe, developer, automation, power, custom
}

public struct PermissionProfileSpec: Codable, Sendable {
    public let profile: PermissionProfile
    public let allowFileRead: Bool
    public let allowFileWrite: Bool
    public let allowShell: Bool
    public let allowGitWrite: Bool
    public let allowTriggers: Bool
    public let allowMCP: Bool
    public let allowWorkers: Bool

    public static let safe = PermissionProfileSpec(
        profile: .safe, allowFileRead: false, allowFileWrite: false,
        allowShell: false, allowGitWrite: false, allowTriggers: false,
        allowMCP: false, allowWorkers: false
    )

    public static let developer = PermissionProfileSpec(
        profile: .developer, allowFileRead: true, allowFileWrite: false,
        allowShell: false, allowGitWrite: false, allowTriggers: false,
        allowMCP: false, allowWorkers: false
    )

    public static let automation = PermissionProfileSpec(
        profile: .automation, allowFileRead: true, allowFileWrite: false,
        allowShell: false, allowGitWrite: false, allowTriggers: true,
        allowMCP: false, allowWorkers: true
    )

    public static let power = PermissionProfileSpec(
        profile: .power, allowFileRead: true, allowFileWrite: true,
        allowShell: true, allowGitWrite: false, allowTriggers: true,
        allowMCP: true, allowWorkers: true
    )

    public init(profile: PermissionProfile, allowFileRead: Bool, allowFileWrite: Bool,
                allowShell: Bool, allowGitWrite: Bool, allowTriggers: Bool,
                allowMCP: Bool, allowWorkers: Bool) {
        self.profile = profile; self.allowFileRead = allowFileRead
        self.allowFileWrite = allowFileWrite; self.allowShell = allowShell
        self.allowGitWrite = allowGitWrite; self.allowTriggers = allowTriggers
        self.allowMCP = allowMCP; self.allowWorkers = allowWorkers
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Import wizard
// ═══════════════════════════════════════════════════════════════════

public enum ImportSource: String, Codable, Sendable, CaseIterable {
    case hermes, openClaw, claudeCode, codex, mcpConfig
}

public struct ImportPreview: Codable, Sendable {
    public let source: ImportSource
    public let foundMemories: Int
    public let foundSkills: Int
    public let foundJobs: Int
    public let foundSecrets: Int
    public let foundMCPServers: Int
    public let warnings: [String]

    public init(source: ImportSource, foundMemories: Int = 0, foundSkills: Int = 0,
                foundJobs: Int = 0, foundSecrets: Int = 0, foundMCPServers: Int = 0,
                warnings: [String] = []) {
        self.source = source; self.foundMemories = foundMemories
        self.foundSkills = foundSkills; self.foundJobs = foundJobs
        self.foundSecrets = foundSecrets; self.foundMCPServers = foundMCPServers
        self.warnings = warnings
    }
}

public struct ImportResult: Codable, Sendable {
    public let source: ImportSource
    public let memoryCandidatesCreated: Int
    public let secretsImportedToKeychain: Int
    public let jobsImportedDisabled: Int
    public let mcpServersImportedDisabled: Int
    public let skippedItems: [String]

    public init(source: ImportSource, memoryCandidatesCreated: Int = 0,
                secretsImportedToKeychain: Int = 0, jobsImportedDisabled: Int = 0,
                mcpServersImportedDisabled: Int = 0, skippedItems: [String] = []) {
        self.source = source; self.memoryCandidatesCreated = memoryCandidatesCreated
        self.secretsImportedToKeychain = secretsImportedToKeychain
        self.jobsImportedDisabled = jobsImportedDisabled
        self.mcpServersImportedDisabled = mcpServersImportedDisabled
        self.skippedItems = skippedItems
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Setup audit
// ═══════════════════════════════════════════════════════════════════

public struct SetupAuditEvent: Codable, Sendable {
    public let kind: SetupAuditKind
    public let message: String
    public let createdAt: Date

    public init(kind: SetupAuditKind, message: String, createdAt: Date = Date()) {
        self.kind = kind; self.message = message; self.createdAt = createdAt
    }
}

public enum SetupAuditKind: String, Codable, Sendable {
    case started, stepDetected, stepConfigured, stepVerified, stepFailed, completed
    case importPreviewed, importApplied, importSkippedItem, importSecretToKeychain
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - User-facing error
// ═══════════════════════════════════════════════════════════════════

public struct SwooshUserFacingError: Codable, Sendable {
    public let code: String
    public let title: String
    public let message: String
    public let recoverySteps: [String]
    public let relatedCommand: String?

    public init(code: String, title: String, message: String,
                recoverySteps: [String] = [], relatedCommand: String? = nil) {
        self.code = code; self.title = title; self.message = message
        self.recoverySteps = recoverySteps; self.relatedCommand = relatedCommand
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Secret store protocol
// ═══════════════════════════════════════════════════════════════════

public struct SecretRef: Codable, Sendable, Hashable {
    public let namespace: String
    public let key: String

    public init(namespace: String, key: String) {
        self.namespace = namespace; self.key = key
    }

    public var displayKey: String { "\(namespace).\(key)" }
}

public protocol SecretStoring: Sendable {
    func setSecret(_ value: String, ref: SecretRef) async throws
    func getSecret(ref: SecretRef) async throws -> String
    func deleteSecret(ref: SecretRef) async throws
    func listSecretRefs(namespace: String?) async throws -> [SecretRef]
}

/// In-memory mock for testing. Real impl uses Keychain.
public actor InMemorySecretStore: SecretStoring {
    private var secrets: [SecretRef: String] = [:]

    public init() {}

    public func setSecret(_ value: String, ref: SecretRef) { secrets[ref] = value }
    public func getSecret(ref: SecretRef) throws -> String {
        guard let v = secrets[ref] else { throw SecretStoreError.notFound(ref.displayKey) }
        return v
    }
    public func deleteSecret(ref: SecretRef) { secrets.removeValue(forKey: ref) }
    public func listSecretRefs(namespace: String?) -> [SecretRef] {
        let refs = Array(secrets.keys)
        if let ns = namespace { return refs.filter { $0.namespace == ns } }
        return refs
    }
}

public enum SecretStoreError: Error, Sendable {
    case notFound(String)
    case accessDenied(String)
}
