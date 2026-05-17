// SwooshDoctor/DoctorTypes.swift — 0.9A Doctor + Debug Bundle + Privacy Report
//
// System diagnostics, privacy auditing, debug bundle generation.
// Debug bundles are always redacted. Privacy reports detect leaks.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Doctor check protocol
// ═══════════════════════════════════════════════════════════════════

public protocol DoctorCheck: Sendable {
    var id: String { get }
    var title: String { get }
    var category: DoctorCategory { get }

    func run(context: DoctorContext) async throws -> DoctorCheckResult
}

public struct DoctorContext: Sendable {
    public let configPath: String
    public let statePath: String
    public let logPath: String

    public init(configPath: String = "~/.swoosh/config.yaml",
                statePath: String = "~/Library/Application Support/Swoosh/state",
                logPath: String = "~/Library/Application Support/Swoosh/logs") {
        self.configPath = configPath; self.statePath = statePath; self.logPath = logPath
    }
}

public enum DoctorCategory: String, Codable, Sendable, CaseIterable {
    case installation, daemon, config, secrets, model
    case permissions, storage, workflows, approvals, board
    case mcp, plugins, privacy
}

public enum DoctorCheckStatus: String, Codable, Sendable {
    case pass, warning, fail, skipped
}

public struct DoctorCheckResult: Codable, Sendable {
    public let checkID: String
    public let title: String
    public let category: DoctorCategory
    public let status: DoctorCheckStatus
    public let message: String?
    public let fixCommand: String?

    public init(checkID: String, title: String, category: DoctorCategory,
                status: DoctorCheckStatus, message: String? = nil, fixCommand: String? = nil) {
        self.checkID = checkID; self.title = title; self.category = category
        self.status = status; self.message = message; self.fixCommand = fixCommand
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Doctor report
// ═══════════════════════════════════════════════════════════════════

public struct DoctorReport: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public let checks: [DoctorCheckResult]
    public let summary: DoctorSummary

    public init(id: String = UUID().uuidString, createdAt: Date = Date(),
                checks: [DoctorCheckResult]) {
        self.id = id; self.createdAt = createdAt; self.checks = checks
        self.summary = DoctorSummary(
            passed: checks.filter { $0.status == .pass }.count,
            warnings: checks.filter { $0.status == .warning }.count,
            failures: checks.filter { $0.status == .fail }.count,
            skipped: checks.filter { $0.status == .skipped }.count
        )
    }

    public var isHealthy: Bool { summary.failures == 0 }
}

public struct DoctorSummary: Codable, Sendable {
    public let passed: Int
    public let warnings: Int
    public let failures: Int
    public let skipped: Int

    public init(passed: Int, warnings: Int, failures: Int, skipped: Int) {
        self.passed = passed; self.warnings = warnings
        self.failures = failures; self.skipped = skipped
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Privacy report
// ═══════════════════════════════════════════════════════════════════

public struct PrivacyReport: Codable, Sendable {
    public let approvedMemoryCount: Int
    public let pendingMemoryCandidateCount: Int
    public let rejectedMemoryCount: Int
    public let rawScoutRecordsRetained: Bool
    public let cookieLikeDataFound: Bool
    public let secretLikeDataFoundInLogs: Bool
    public let rawTokensFoundInConfig: Bool
    public let privateKeysFound: Bool
    public let seedPhrasesFound: Bool
    public let createdAt: Date

    public init(approvedMemoryCount: Int = 0, pendingMemoryCandidateCount: Int = 0,
                rejectedMemoryCount: Int = 0, rawScoutRecordsRetained: Bool = false,
                cookieLikeDataFound: Bool = false, secretLikeDataFoundInLogs: Bool = false,
                rawTokensFoundInConfig: Bool = false, privateKeysFound: Bool = false,
                seedPhrasesFound: Bool = false, createdAt: Date = Date()) {
        self.approvedMemoryCount = approvedMemoryCount
        self.pendingMemoryCandidateCount = pendingMemoryCandidateCount
        self.rejectedMemoryCount = rejectedMemoryCount
        self.rawScoutRecordsRetained = rawScoutRecordsRetained
        self.cookieLikeDataFound = cookieLikeDataFound
        self.secretLikeDataFoundInLogs = secretLikeDataFoundInLogs
        self.rawTokensFoundInConfig = rawTokensFoundInConfig
        self.privateKeysFound = privateKeysFound
        self.seedPhrasesFound = seedPhrasesFound
        self.createdAt = createdAt
    }

    public var isClean: Bool {
        !cookieLikeDataFound && !secretLikeDataFoundInLogs &&
        !rawTokensFoundInConfig && !privateKeysFound && !seedPhrasesFound
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Privacy scanner
// ═══════════════════════════════════════════════════════════════════

public struct PrivacyScanner: Sendable {
    private static let secretPatterns = [
        "-----BEGIN PRIVATE KEY", "-----BEGIN RSA PRIVATE KEY",
        "sk_live_", "sk_test_", "xprv", "Bearer ",
        "api_key=", "token=", "password=",
    ]
    private static let cookiePatterns = [
        "cookie:", "Set-Cookie:", "session_id=", "csrf_token=",
    ]
    private static let seedPatterns = [
        "seed:", "mnemonic:", "recovery phrase:",
    ]

    public init() {}

    public func scanText(_ text: String) -> PrivacyScanResult {
        var issues: [String] = []
        for p in Self.secretPatterns {
            if text.contains(p) { issues.append("Secret pattern found: \(p.prefix(10))…") }
        }
        for p in Self.cookiePatterns {
            if text.contains(p) { issues.append("Cookie pattern found: \(p.prefix(10))…") }
        }
        for p in Self.seedPatterns {
            if text.contains(p) { issues.append("Seed pattern found: \(p.prefix(10))…") }
        }
        return PrivacyScanResult(
            hasSecrets: Self.secretPatterns.contains { text.contains($0) },
            hasCookies: Self.cookiePatterns.contains { text.contains($0) },
            hasSeedPhrases: Self.seedPatterns.contains { text.contains($0) },
            issues: issues
        )
    }
}

public struct PrivacyScanResult: Codable, Sendable {
    public let hasSecrets: Bool
    public let hasCookies: Bool
    public let hasSeedPhrases: Bool
    public let issues: [String]

    public init(hasSecrets: Bool, hasCookies: Bool, hasSeedPhrases: Bool, issues: [String]) {
        self.hasSecrets = hasSecrets; self.hasCookies = hasCookies
        self.hasSeedPhrases = hasSeedPhrases; self.issues = issues
    }

    public var isClean: Bool { !hasSecrets && !hasCookies && !hasSeedPhrases }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Debug bundle
// ═══════════════════════════════════════════════════════════════════

public struct DebugBundle: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public let doctorReport: DoctorReport
    public let privacyReport: PrivacyReport
    public let redactedConfig: String
    public let moduleVersions: [String: String]
    public let auditSummary: String
    public let daemonStatus: String

    public init(id: String = UUID().uuidString, createdAt: Date = Date(),
                doctorReport: DoctorReport, privacyReport: PrivacyReport,
                redactedConfig: String, moduleVersions: [String: String] = [:],
                auditSummary: String = "", daemonStatus: String = "unknown") {
        self.id = id; self.createdAt = createdAt
        self.doctorReport = doctorReport; self.privacyReport = privacyReport
        self.redactedConfig = redactedConfig; self.moduleVersions = moduleVersions
        self.auditSummary = auditSummary; self.daemonStatus = daemonStatus
    }
}

/// Redacts config content for debug bundles
public struct DebugBundleRedactor: Sendable {
    private static let redactPatterns = [
        "api_key", "token", "secret", "password", "Bearer",
        "-----BEGIN", "PRIVATE KEY", "sk_", "xprv", "mnemonic",
        "seed:", "cookie:", "session_token",
    ]

    public init() {}

    public func redactConfig(_ config: String) -> String {
        var result = config
        for pattern in Self.redactPatterns {
            if result.contains(pattern) {
                // Redact the line containing the pattern
                let lines = result.components(separatedBy: "\n")
                result = lines.map { line in
                    if line.contains(pattern) { return "# [REDACTED]" }
                    return line
                }.joined(separator: "\n")
            }
        }
        return result
    }
}
