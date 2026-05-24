// SwooshScout/Scout.swift — 0.9S First-run personalization scanner
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

/// Outcome of `ScoutSource.checkPermission()` / `requestPermission()`.
/// `notDetermined` means the user has never been asked; `restricted`
/// means the OS denies the request regardless of user consent (parental
/// controls, MDM, missing entitlement, unsupported platform).
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
    case recentDocument        // Recent doc per-app via Apple's sharedfilelist
    case personalizationSignal // Passive Swoosh runtime signal aggregate

    // NOTE: `musicHistory` and `screenTime` were declared as planned
    // tags but never produced by any source. Removed in 0.9S — no
    // Scout records carry these values (verified via repo grep) so
    // removal does not break any persisted ledger. Re-add when the
    // matching producer (`MusicHistorySource` / `ScreenTimeSource`)
    // actually lands.
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

    /// Single redaction rule — paired (regex, replacement template). The
    /// list is iterated in order; order matters when patterns overlap.
    fileprivate struct Rule: Sendable {
        let regex: NSRegularExpression
        let replacement: String
    }

    /// Compiled once at module load. Avoids the per-call regex compile
    /// cost the previous implementation paid (`try? NSRegularExpression`
    /// inside the loop) — for a corpus of hundreds of records that adds
    /// up to noticeable startup latency for `swoosh setup`.
    fileprivate static let rules: [Rule] = [
        // API keys (common patterns)
        rule(#"(sk-[a-zA-Z0-9]{20,})"#, "[REDACTED_API_KEY]"),
        rule(#"(ghp_[a-zA-Z0-9]{36,})"#, "[REDACTED_GITHUB_TOKEN]"),
        rule(#"(xoxb-[a-zA-Z0-9\-]{20,})"#, "[REDACTED_SLACK_TOKEN]"),
        // Bearer tokens
        rule(#"Bearer\s+[a-zA-Z0-9\._\-]{20,}"#, "Bearer [REDACTED]"),
        // SSH private keys (RSA / EC / OPENSSH / DSA header variants)
        rule(pemPrivateKeyPattern, "[REDACTED_PRIVATE_KEY]"),
        // Generic long hex/base64 tokens
        rule(#"[a-f0-9]{64,}"#, "[REDACTED_HEX_TOKEN]"),
        // .env style secrets
        rule(#"(?i)(password|secret|token|api_key|apikey)\s*=\s*\S+"#, "$1=[REDACTED]"),
        // Cookie values (key=value with long values)
        rule(#"(?i)(cookie|session_id|csrf)[:=]\s*[a-zA-Z0-9\+/=]{32,}"#, "$1=[REDACTED_COOKIE]")
    ]

    public init() {}

    public func redact(_ record: ScoutRecord) -> ScoutRecord {
        var text = record.content
        for rule in Self.rules {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = rule.regex.stringByReplacingMatches(in: text, range: range, withTemplate: rule.replacement)
        }
        return ScoutRecord(
            sourceID: record.sourceID,
            kind: record.kind,
            sensitivity: record.sensitivity,
            content: text,
            metadata: record.metadata
        )
    }

    /// Static-let-friendly constructor. `try!` is safe here because the
    /// patterns are compile-time literal regexes verified at module
    /// load — any breakage shows up the first time tests touch
    /// `SecretRedactor`. A regex literal that fails to compile is a
    /// programming error, not runtime input.
    fileprivate static func rule(_ pattern: String, _ replacement: String) -> Rule {
        // swiftlint:disable:next force_try
        Rule(regex: try! NSRegularExpression(pattern: pattern), replacement: replacement)
    }

    /// Hoisted out of the table literal so the longest individual
    /// pattern doesn't push the row onto a 130-character line.
    fileprivate static let pemPrivateKeyPattern: String = {
        let header = #"-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"#
        let footer = #"-----END (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"#
        return header + #"[\s\S]*?"# + footer
    }()
}
