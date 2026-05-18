// SwooshTools/ScoutAuditToolTypes.swift — Scout and Audit tool types
import Foundation

// MARK: - Scout tools
// ═══════════════════════════════════════════════════════════════════

// ── scout.list_sources ────────────────────────────────────────────

public struct ScoutListSourcesInput: Codable, Sendable {
    public init() {}
}

public struct ScoutListSourcesOutput: Codable, Sendable {
    public let sources: [ScoutSourceInfo]

    public init(sources: [ScoutSourceInfo]) {
        self.sources = sources
    }
}

public struct ScoutSourceInfo: Codable, Sendable {
    public let sourceID: String
    public let displayName: String
    public let kind: String
    public let enabled: Bool

    public init(sourceID: String, displayName: String, kind: String, enabled: Bool) {
        self.sourceID = sourceID
        self.displayName = displayName
        self.kind = kind
        self.enabled = enabled
    }
}

// ── scout.status ──────────────────────────────────────────────────

public struct ScoutStatusInput: Codable, Sendable {
    public init() {}
}

public struct ScoutStatusOutput: Codable, Sendable {
    public let lastScanDate: Date?
    public let recordCount: Int
    public let candidateCount: Int

    public init(lastScanDate: Date?, recordCount: Int, candidateCount: Int) {
        self.lastScanDate = lastScanDate
        self.recordCount = recordCount
        self.candidateCount = candidateCount
    }
}

// ── scout.run ─────────────────────────────────────────────────────

public struct ScoutRunInput: Codable, Sendable {
    public let sourceIDs: [String]
    public let selectedFolderBookmarks: [String]
    public let dryRun: Bool

    public init(sourceIDs: [String], selectedFolderBookmarks: [String] = [], dryRun: Bool = false) {
        self.sourceIDs = sourceIDs
        self.selectedFolderBookmarks = selectedFolderBookmarks
        self.dryRun = dryRun
    }
}

public struct ScoutRunOutput: Codable, Sendable {
    public let scanID: String
    public let recordsCreated: Int
    public let candidatesCreated: Int
    public let skippedSources: [SkippedScoutSource]

    public init(scanID: String, recordsCreated: Int, candidatesCreated: Int, skippedSources: [SkippedScoutSource]) {
        self.scanID = scanID
        self.recordsCreated = recordsCreated
        self.candidatesCreated = candidatesCreated
        self.skippedSources = skippedSources
    }
}

public struct SkippedScoutSource: Codable, Sendable {
    public let sourceID: String
    public let reason: String

    public init(sourceID: String, reason: String) {
        self.sourceID = sourceID
        self.reason = reason
    }
}

// ── scout.get_report ──────────────────────────────────────────────

public struct ScoutGetReportInput: Codable, Sendable {
    public let scanID: String?

    public init(scanID: String? = nil) {
        self.scanID = scanID
    }
}

public struct ScoutGetReportOutput: Codable, Sendable {
    public let reportMarkdown: String
    public let scanID: String?

    public init(reportMarkdown: String, scanID: String?) {
        self.reportMarkdown = reportMarkdown
        self.scanID = scanID
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Audit tools
// ═══════════════════════════════════════════════════════════════════

// ── audit.tail ────────────────────────────────────────────────────

public struct AuditTailInput: Codable, Sendable {
    public let limit: Int?
    public let eventTypes: [String]?

    public init(limit: Int? = nil, eventTypes: [String]? = nil) {
        self.limit = limit
        self.eventTypes = eventTypes
    }
}

public struct AuditTailOutput: Codable, Sendable {
    public let events: [AuditEntry]

    public init(events: [AuditEntry]) {
        self.events = events
    }
}

// ── audit.search ──────────────────────────────────────────────────

public struct AuditSearchInput: Codable, Sendable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct AuditSearchOutput: Codable, Sendable {
    public let events: [AuditEntry]

    public init(events: [AuditEntry]) {
        self.events = events
    }
}

// ── audit.get_event ───────────────────────────────────────────────

public struct AuditGetEventInput: Codable, Sendable {
    public let eventID: String

    public init(eventID: String) {
        self.eventID = eventID
    }
}

public struct AuditGetEventOutput: Codable, Sendable {
    public let event: AuditEntry?

    public init(event: AuditEntry?) {
        self.event = event
    }
}
