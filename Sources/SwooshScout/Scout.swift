// SwooshScout/Scout.swift — First-run personalization scanner
//
// "Collect context, not secrets. Learn workflows, not credentials."
//
// Scout scans local data sources the user approves, generates memory candidates,
// redacts secrets, and requires review before anything becomes durable memory.

import Foundation

// MARK: - Scout source protocol

/// Each data source is a typed Swift module.
public protocol ScoutSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var description: String { get }
    var sensitivity: Sensitivity { get }
    var requiredPermissions: [String] { get }

    /// Check if this source is accessible.
    func checkPermission() async throws -> SourcePermissionStatus

    /// Request permission from the OS / user.
    func requestPermission() async throws -> SourcePermissionStatus

    /// Scan and produce records. Streams for progress reporting.
    func scan(progress: ScanProgress) async throws -> [ScoutRecord]
}

// MARK: - Sensitivity levels

public enum Sensitivity: String, Codable, Sendable, Comparable {
    case low        // device info, installed apps
    case medium     // file structures, calendar patterns
    case high       // contacts, email, notes
    case critical   // passwords, tokens, cookies — NEVER ingest

    public static func < (lhs: Sensitivity, rhs: Sensitivity) -> Bool {
        let order: [Sensitivity] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

public enum SourcePermissionStatus: Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
}

// MARK: - Scan progress

public actor ScanProgress {
    public var currentSource: String = ""
    public var recordsFound: Int = 0
    public var recordsRedacted: Int = 0

    public init() {}

    public func update(source: String, found: Int, redacted: Int) {
        self.currentSource = source
        self.recordsFound = found
        self.recordsRedacted = redacted
    }
}

// MARK: - Scout record

public struct ScoutRecord: Codable, Sendable {
    public let sourceID: String
    public let kind: RecordKind
    public let sensitivity: Sensitivity
    public let content: String
    public let metadata: [String: String]

    public init(sourceID: String, kind: RecordKind, sensitivity: Sensitivity, content: String, metadata: [String: String] = [:]) {
        self.sourceID = sourceID
        self.kind = kind
        self.sensitivity = sensitivity
        self.content = content
        self.metadata = metadata
    }
}

public enum RecordKind: String, Codable, Sendable {
    case deviceInfo
    case installedApp
    case runningApp
    case fileStructure
    case projectInfo
    case calendarPattern
    case reminderSummary
    case contactRelationship
    case browserDomain
    case browserBookmark
    case noteSummary
    case shellEnvironment
    case gitRepo
    case xcodeProject
    case mcpConfig
    case hermesImport

    // ── Personal-data sources ─────────────────────────────────────
    case focusMode             // What focus profile the user typically inhabits
    case appUsage              // Per-app focus time aggregated over a window
    case calendarEvent         // One calendar event (anonymized by the source)
    case reminderItem          // Pending/recently-completed reminder
    case healthSleep           // Sleep duration summary, not raw heart-rate data
    case healthActivity        // Step / move ring summary
    case musicHistory          // Recently-played music aggregate
    case recentDocument        // Recent doc per-app via Apple's sharedfilelist
    case screenTime            // iOS DeviceActivity bucket
    case personalizationSignal // Passive Swoosh runtime signal aggregate
}

// MARK: - Memory candidate

public struct MemoryCandidate: Codable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let category: String  // maps to MemoryCategory
    public let confidence: Double
    public let sensitivity: Sensitivity
    public let evidence: [EvidencePointer]
    public let recommendedTTL: TimeInterval?

    public init(
        id: UUID = UUID(),
        text: String,
        category: String,
        confidence: Double,
        sensitivity: Sensitivity,
        evidence: [EvidencePointer] = [],
        recommendedTTL: TimeInterval? = nil
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.confidence = confidence
        self.sensitivity = sensitivity
        self.evidence = evidence
        self.recommendedTTL = recommendedTTL
    }
}

public struct EvidencePointer: Codable, Sendable {
    public let source: String
    public let detail: String

    public init(source: String, detail: String) {
        self.source = source
        self.detail = detail
    }
}

// MARK: - Personalization depth

public enum PersonalizationDepth: String, Codable, Sendable, CaseIterable {
    /// Device, installed apps, selected folders.
    case minimal

    /// + calendar, reminders, dev tools, browser tabs/bookmarks.
    case recommended

    /// + contacts, notes, mail, browser history, screen sampling. Full review required.
    case deep

    /// User chooses exact sources.
    case custom
}

// MARK: - Secret redactor

/// Strips secrets before model context. The model should not see raw secrets.
public struct SecretRedactor: Sendable {
    public init() {}

    public func redact(_ record: ScoutRecord) -> ScoutRecord {
        var text = record.content

        // API keys (common patterns)
        text = redactPattern(text, pattern: #"(sk-[a-zA-Z0-9]{20,})"#, replacement: "[REDACTED_API_KEY]")
        text = redactPattern(text, pattern: #"(ghp_[a-zA-Z0-9]{36,})"#, replacement: "[REDACTED_GITHUB_TOKEN]")
        text = redactPattern(text, pattern: #"(xoxb-[a-zA-Z0-9\-]{20,})"#, replacement: "[REDACTED_SLACK_TOKEN]")

        // Bearer tokens
        text = redactPattern(text, pattern: #"Bearer\s+[a-zA-Z0-9\._\-]{20,}"#, replacement: "Bearer [REDACTED]")

        // SSH private keys
        text = redactPattern(text, pattern: #"-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----[\s\S]*?-----END (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"#, replacement: "[REDACTED_PRIVATE_KEY]")

        // Generic long hex/base64 tokens
        text = redactPattern(text, pattern: #"[a-f0-9]{64,}"#, replacement: "[REDACTED_HEX_TOKEN]")

        // .env style secrets
        text = redactPattern(text, pattern: #"(?i)(password|secret|token|api_key|apikey)\s*=\s*\S+"#, replacement: "$1=[REDACTED]")

        // Cookie values (key=value with long values)
        text = redactPattern(text, pattern: #"(?i)(cookie|session_id|csrf)[:=]\s*[a-zA-Z0-9\+/=]{32,}"#, replacement: "$1=[REDACTED_COOKIE]")

        return ScoutRecord(
            sourceID: record.sourceID,
            kind: record.kind,
            sensitivity: record.sensitivity,
            content: text,
            metadata: record.metadata
        )
    }

    private func redactPattern(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
