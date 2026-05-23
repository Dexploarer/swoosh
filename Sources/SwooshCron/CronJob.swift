// SwooshCron/CronJob.swift — 0.5A Durable scheduled agent jobs
//
// 0.5A: removed unused `deliver` field. It had zero consumers — declared,
// persisted, accepted via CLI + agent tool, but never read. Existing
// jobs.json files with a `deliver` key still decode (JSONDecoder ignores
// unknown keys by default); the field simply stops round-tripping out.
import Foundation
import SwooshTools

public struct CronJob: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var prompt: String
    public var schedule: CronSchedule
    public var skills: [String]
    public var enabledToolsets: [String]?
    public var repeatLimit: Int?
    public var completedRuns: Int
    public var state: CronJobState
    public var enabled: Bool
    public var nextRunAt: Date?
    public var lastRunAt: Date?
    public var lastStatus: CronRunStatus?
    public var createdAt: Date
    public var updatedAt: Date
    public var model: String?
    public var provider: String?
    public var script: String?
    public var noAgent: Bool
    public var contextFrom: [String]
    public var workdir: String?

    public init(
        id: String = String(UUID().uuidString.prefix(12)),
        name: String,
        prompt: String,
        schedule: CronSchedule,
        skills: [String] = [],
        enabledToolsets: [String]? = nil,
        repeatLimit: Int? = nil,
        state: CronJobState = .scheduled,
        enabled: Bool = true,
        model: String? = nil,
        provider: String? = nil,
        script: String? = nil,
        noAgent: Bool = false,
        contextFrom: [String] = [],
        workdir: String? = nil,
        now: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.skills = skills
        self.enabledToolsets = enabledToolsets
        self.repeatLimit = repeatLimit
        self.completedRuns = 0
        self.state = state
        self.enabled = enabled
        self.nextRunAt = CronScheduleParser.nextRun(after: now, schedule: schedule)
        self.lastRunAt = nil
        self.lastStatus = nil
        self.createdAt = now
        self.updatedAt = now
        self.model = model
        self.provider = provider
        self.script = script
        self.noAgent = noAgent
        self.contextFrom = contextFrom
        self.workdir = workdir
    }
}

public enum CronJobState: String, Codable, Sendable {
    case scheduled
    case paused
    case running
    case completed
    case failed
}

public enum CronRunStatus: String, Codable, Sendable {
    case ok
    case skipped
    case failed
}

public typealias CronSchedule = SwooshSchedule
public typealias CronScheduleKind = SwooshScheduleKind

public struct CronRunRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let jobID: String
    public let startedAt: Date
    public let finishedAt: Date
    public let status: CronRunStatus
    public let outputPath: String?
    public let summary: String

    public init(id: String = UUID().uuidString, jobID: String, startedAt: Date, finishedAt: Date, status: CronRunStatus, outputPath: String?, summary: String) {
        self.id = id
        self.jobID = jobID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.outputPath = outputPath
        self.summary = summary
    }
}

public struct CronExecutionRequest: Sendable {
    public let job: CronJob
    public let sessionID: String
    public let prompt: String
    public let workdir: URL?
    public let skills: [String]
    public let enabledToolsets: [String]?

    public init(job: CronJob, sessionID: String, prompt: String, workdir: URL?, skills: [String], enabledToolsets: [String]?) {
        self.job = job
        self.sessionID = sessionID
        self.prompt = prompt
        self.workdir = workdir
        self.skills = skills
        self.enabledToolsets = enabledToolsets
    }
}

public typealias CronAgentExecutor = @Sendable (CronExecutionRequest) async throws -> String
