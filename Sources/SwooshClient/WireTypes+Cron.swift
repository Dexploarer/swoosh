// SwooshClient/WireTypes+Cron.swift — 0.4A Tier 1 Cron CRUD wire types
//
// Wire format for `GET /api/cron`, `POST /api/cron`,
// `DELETE /api/cron/{id}`, and `POST /api/cron/{id}/run`.
// `CronJobRecordSummary` lives in WireTypes+Records.swift because the
// dashboard records endpoint reuses it.

import Foundation

public struct CronJobsResponse: Codable, Sendable, Equatable {
    public let jobs: [CronJobRecordSummary]

    public init(jobs: [CronJobRecordSummary]) {
        self.jobs = jobs
    }
}

public struct CronJobCreateRequest: Codable, Sendable, Equatable {
    public let name: String
    public let prompt: String
    public let schedule: String       // natural-language: "every 5 minutes", "daily at 9am"
    public let enabled: Bool?
    public let model: String?
    public let provider: String?
    public let skills: [String]?
    public let enabledToolsets: [String]?
    public let workdir: String?

    public init(
        name: String,
        prompt: String,
        schedule: String,
        enabled: Bool? = nil,
        model: String? = nil,
        provider: String? = nil,
        skills: [String]? = nil,
        enabledToolsets: [String]? = nil,
        workdir: String? = nil
    ) {
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.enabled = enabled
        self.model = model
        self.provider = provider
        self.skills = skills
        self.enabledToolsets = enabledToolsets
        self.workdir = workdir
    }
}

public struct CronJobMutationResponse: Codable, Sendable, Equatable {
    public let job: CronJobRecordSummary
    public let message: String

    public init(job: CronJobRecordSummary, message: String) {
        self.job = job
        self.message = message
    }
}
