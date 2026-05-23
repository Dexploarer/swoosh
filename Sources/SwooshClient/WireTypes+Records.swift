// SwooshClient/WireTypes+Records.swift — 0.4A Cross-cutting record summaries
//
// Memory/Goal/Manifestation/Cron record summaries, plus media-gallery
// listings and the aggregated `RecordsResponse` consumed by the
// dashboard. Goal/Manifestation/Cron *CRUD* lives in their own files;
// this file holds the trimmed projections that several endpoints share.

import Foundation

public struct MemorySummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let text: String
    public let category: String
    public let status: String
    public let sensitivity: String
    public let confidence: Double?
    public let createdAt: String

    public init(
        id: String,
        text: String,
        category: String,
        status: String,
        sensitivity: String,
        confidence: Double?,
        createdAt: String
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.status = status
        self.sensitivity = sensitivity
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

public struct MemoriesResponse: Codable, Sendable {
    public let approved: [MemorySummary]
    public let pending: [MemorySummary]
    public let rejected: [MemorySummary]

    public init(approved: [MemorySummary], pending: [MemorySummary], rejected: [MemorySummary] = []) {
        self.approved = approved
        self.pending = pending
        self.rejected = rejected
    }
}

public struct GoalRecordSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let statement: String
    public let state: String
    public let progress: String
    public let updatedAt: Date

    public init(id: String, statement: String, state: String, progress: String, updatedAt: Date) {
        self.id = id
        self.statement = statement
        self.state = state
        self.progress = progress
        self.updatedAt = updatedAt
    }
}

public struct ManifestationRecordSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let status: String
    public let triggerReason: String
    public let proposalCount: Int
    public let summary: String?
    public let startedAt: Date

    public init(
        id: String,
        status: String,
        triggerReason: String,
        proposalCount: Int,
        summary: String?,
        startedAt: Date
    ) {
        self.id = id
        self.status = status
        self.triggerReason = triggerReason
        self.proposalCount = proposalCount
        self.summary = summary
        self.startedAt = startedAt
    }
}

public struct CronJobRecordSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let state: String
    public let enabled: Bool
    public let nextRunAt: Date?
    public let lastRunAt: Date?

    public init(id: String, name: String, state: String, enabled: Bool, nextRunAt: Date?, lastRunAt: Date?) {
        self.id = id
        self.name = name
        self.state = state
        self.enabled = enabled
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
    }
}

public struct RecordsResponse: Codable, Sendable {
    public let readiness: SwooshReadinessReport
    public let metrics: MetricsResponse
    public let usage: UsageResponse
    public let boardCards: [BoardCardSummary]
    public let goals: [GoalRecordSummary]
    public let manifestations: [ManifestationRecordSummary]
    public let cronJobs: [CronJobRecordSummary]
    public let generatedAt: Date

    public init(
        readiness: SwooshReadinessReport,
        metrics: MetricsResponse,
        usage: UsageResponse,
        boardCards: [BoardCardSummary],
        goals: [GoalRecordSummary],
        manifestations: [ManifestationRecordSummary],
        cronJobs: [CronJobRecordSummary],
        generatedAt: Date = Date()
    ) {
        self.readiness = readiness
        self.metrics = metrics
        self.usage = usage
        self.boardCards = boardCards
        self.goals = goals
        self.manifestations = manifestations
        self.cronJobs = cronJobs
        self.generatedAt = generatedAt
    }
}

public enum MediaGalleryKind: String, Codable, Sendable {
    case image
    case video
    case audio
    case other
}

public struct MediaGalleryItem: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let kind: MediaGalleryKind
    public let relativePath: String
    public let byteSize: Int64
    public let createdAt: Date?

    public init(
        id: String,
        title: String,
        kind: MediaGalleryKind,
        relativePath: String,
        byteSize: Int64,
        createdAt: Date?
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.createdAt = createdAt
    }
}

public struct MediaGalleryResponse: Codable, Sendable {
    public let items: [MediaGalleryItem]
    public let root: String
    public let generatedAt: Date

    public init(items: [MediaGalleryItem], root: String, generatedAt: Date = Date()) {
        self.items = items
        self.root = root
        self.generatedAt = generatedAt
    }
}
