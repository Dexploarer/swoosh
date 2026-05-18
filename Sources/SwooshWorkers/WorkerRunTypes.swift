// SwooshWorkers/WorkerRunTypes.swift — Heartbeat, log, artifact, result, escalation, isolation, redactor
import Foundation

// MARK: - Worker heartbeat
// ═══════════════════════════════════════════════════════════════════

public struct WorkerHeartbeat: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let cardID: String
    public let status: WorkerRunStatus
    public let message: String?
    public let toolCallCount: Int
    public let turnCount: Int
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, runID: String, cardID: String,
        status: WorkerRunStatus, message: String? = nil,
        toolCallCount: Int = 0, turnCount: Int = 0, createdAt: Date = Date()
    ) {
        self.id = id; self.runID = runID; self.cardID = cardID
        self.status = status; self.message = message
        self.toolCallCount = toolCallCount; self.turnCount = turnCount; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker log
// ═══════════════════════════════════════════════════════════════════

public struct WorkerLog: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let level: WorkerLogLevel
    public let message: String
    public let createdAt: Date

    public init(id: String = UUID().uuidString, runID: String, level: WorkerLogLevel, message: String, createdAt: Date = Date()) {
        self.id = id; self.runID = runID; self.level = level; self.message = message; self.createdAt = createdAt
    }
}

public enum WorkerLogLevel: String, Codable, Sendable { case info, warning, error, debug }

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker artifact
// ═══════════════════════════════════════════════════════════════════

public struct WorkerArtifact: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let cardID: String
    public let kind: WorkerArtifactKind
    public let title: String
    public let uri: String
    public let preview: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, runID: String, cardID: String,
        kind: WorkerArtifactKind, title: String, uri: String,
        preview: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id; self.runID = runID; self.cardID = cardID
        self.kind = kind; self.title = title; self.uri = uri
        self.preview = preview; self.createdAt = createdAt
    }
}

public enum WorkerArtifactKind: String, Codable, Sendable {
    case report, diff, log, workflowDraft, transactionPreview, diagnosticSummary, other
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker result
// ═══════════════════════════════════════════════════════════════════

public struct WorkerResult: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let cardID: String
    public let status: WorkerRunStatus
    public let summary: String
    public let recommendations: [String]
    public let artifactIDs: [String]
    public let completedAt: Date

    public init(
        id: String = UUID().uuidString, runID: String, cardID: String,
        status: WorkerRunStatus, summary: String, recommendations: [String] = [],
        artifactIDs: [String] = [], completedAt: Date = Date()
    ) {
        self.id = id; self.runID = runID; self.cardID = cardID
        self.status = status; self.summary = summary; self.recommendations = recommendations
        self.artifactIDs = artifactIDs; self.completedAt = completedAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker escalation
// ═══════════════════════════════════════════════════════════════════

public struct WorkerEscalation: Codable, Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let cardID: String
    public let reason: WorkerEscalationReason
    public let message: String
    public let suggestedHumanAction: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString, runID: String, cardID: String,
        reason: WorkerEscalationReason, message: String,
        suggestedHumanAction: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id; self.runID = runID; self.cardID = cardID
        self.reason = reason; self.message = message
        self.suggestedHumanAction = suggestedHumanAction; self.createdAt = createdAt
    }
}

public enum WorkerEscalationReason: String, Codable, Sendable {
    case approvalNeeded, permissionDenied, missingInput, budgetExceeded
    case toolUnavailable, blockedByPolicy, ambiguousTask, failedTool
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Subagent isolation policy
// ═══════════════════════════════════════════════════════════════════

public struct SubagentIsolationPolicy: Codable, Sendable {
    public let separateSession: Bool
    public let separateTranscript: Bool
    public let finalSummaryOnlyToParent: Bool
    public let allowMemoryWrites: Bool
    public let allowBoardWrites: Bool

    public static func forWorker() -> SubagentIsolationPolicy {
        SubagentIsolationPolicy(
            separateSession: true, separateTranscript: true,
            finalSummaryOnlyToParent: true,
            allowMemoryWrites: false, allowBoardWrites: true
        )
    }

    public init(separateSession: Bool, separateTranscript: Bool,
                finalSummaryOnlyToParent: Bool, allowMemoryWrites: Bool, allowBoardWrites: Bool) {
        self.separateSession = separateSession; self.separateTranscript = separateTranscript
        self.finalSummaryOnlyToParent = finalSummaryOnlyToParent
        self.allowMemoryWrites = allowMemoryWrites; self.allowBoardWrites = allowBoardWrites
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker content redactor
// ═══════════════════════════════════════════════════════════════════

public struct WorkerContentRedactor: Sendable {
    private static let sensitivePatterns = [
        "-----BEGIN", "PRIVATE KEY", "sk_", "xprv", "xpub",
        "seed:", "mnemonic:", "cookie:", "session_token",
        "password:", "secret:", "Bearer ",
    ]

    public init() {}

    public func redact(_ text: String) -> String {
        var value = text
        for p in Self.sensitivePatterns {
            if value.contains(p) { value = value.replacingOccurrences(of: p, with: "[REDACTED]") }
        }
        return value
    }
}
