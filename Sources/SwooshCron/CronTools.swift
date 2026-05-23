// SwooshCron/CronTools.swift — 0.5A Single model-facing cronjob tool
//
// 0.5A: removed unused `deliver` argument. It had no downstream consumer.
// Old persisted jobs decode unchanged (JSONDecoder ignores extra keys);
// the model can no longer pass `deliver` in a CronJobToolInput payload.
import Foundation
import SwooshTools

public enum CronJobAction: String, Codable, Sendable {
    case create
    case list
    case update
    case pause
    case resume
    case run
    case remove
}

public struct CronJobToolInput: Codable, Sendable {
    public let action: CronJobAction
    public let id: String?
    public let name: String?
    public let schedule: String?
    public let prompt: String?
    public let skills: [String]?
    public let enabledToolsets: [String]?
    public let repeatLimit: Int?
    public let script: String?
    public let noAgent: Bool?
    public let contextFrom: [String]?
    public let workdir: String?

    public init(
        action: CronJobAction,
        id: String? = nil,
        name: String? = nil,
        schedule: String? = nil,
        prompt: String? = nil,
        skills: [String]? = nil,
        enabledToolsets: [String]? = nil,
        repeatLimit: Int? = nil,
        script: String? = nil,
        noAgent: Bool? = nil,
        contextFrom: [String]? = nil,
        workdir: String? = nil
    ) {
        self.action = action
        self.id = id
        self.name = name
        self.schedule = schedule
        self.prompt = prompt
        self.skills = skills
        self.enabledToolsets = enabledToolsets
        self.repeatLimit = repeatLimit
        self.script = script
        self.noAgent = noAgent
        self.contextFrom = contextFrom
        self.workdir = workdir
    }
}

public struct CronJobToolOutput: Codable, Sendable {
    public let jobs: [CronJob]
    public let run: CronRunRecord?
    public let message: String
}

public struct CronToolDependencies: Sendable {
    public let store: FileCronJobStore
    public let scheduler: CronScheduler?
    public let executor: CronAgentExecutor?

    public init(store: FileCronJobStore = FileCronJobStore(), scheduler: CronScheduler? = nil, executor: CronAgentExecutor? = nil) {
        self.store = store
        self.scheduler = scheduler
        self.executor = executor
    }
}

public struct CronJobTool: SwooshTool {
    public typealias Input = CronJobToolInput
    public typealias Output = CronJobToolOutput
    public static let name: ToolName = "cronjob"
    public static let displayName = "Scheduled Jobs"
    public static let description = "Create, list, update, pause, resume, run, and remove scheduled jobs."
    public static let permission: SwooshPermission = .scheduleWrite
    public static let risk: ToolRisk = .medium
    public static let approval: ApprovalPolicy = .askEveryTime
    public static let toolset: ToolsetID = .cron

    private let store: FileCronJobStore
    private let scheduler: CronScheduler?
    private let executor: CronAgentExecutor?

    public init(dependencies: CronToolDependencies = CronToolDependencies()) {
        self.store = dependencies.store
        self.scheduler = dependencies.scheduler
        self.executor = dependencies.executor
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        switch input.action {
        case .create:
            let job = try CronJob(
                name: input.name ?? input.prompt?.prefix(48).description ?? "Scheduled job",
                prompt: input.prompt.unwrap(or: CronToolError.missingField("prompt")),
                schedule: CronScheduleParser.parse(input.schedule.unwrap(or: CronToolError.missingField("schedule"))),
                skills: input.skills ?? [],
                enabledToolsets: input.enabledToolsets,
                repeatLimit: input.repeatLimit,
                script: input.script,
                noAgent: input.noAgent ?? false,
                contextFrom: input.contextFrom ?? [],
                workdir: input.workdir
            )
            try await store.save(job)
            return Output(jobs: [job], run: nil, message: "created")
        case .list:
            return Output(jobs: try await store.list(), run: nil, message: "listed")
        case .update:
            let id = try input.id.unwrap(or: CronToolError.missingField("id"))
            guard var job = try await store.get(idOrName: id) else { throw CronStoreError.notFound(id) }
            if let name = input.name { job.name = name }
            if let prompt = input.prompt { job.prompt = prompt }
            if let schedule = input.schedule {
                job.schedule = try CronScheduleParser.parse(schedule)
                job.nextRunAt = CronScheduleParser.nextRun(after: Date(), schedule: job.schedule)
            }
            if let skills = input.skills { job.skills = skills }
            if let enabledToolsets = input.enabledToolsets { job.enabledToolsets = enabledToolsets }
            if let repeatLimit = input.repeatLimit { job.repeatLimit = repeatLimit }
            if let script = input.script { job.script = script }
            if let noAgent = input.noAgent { job.noAgent = noAgent }
            if let contextFrom = input.contextFrom { job.contextFrom = contextFrom }
            if let workdir = input.workdir { job.workdir = workdir }
            job.state = job.enabled ? .scheduled : .paused
            try await store.update(job)
            return Output(jobs: [job], run: nil, message: "updated")
        case .pause:
            let job = try await mutateState(id: input.id, state: .paused, enabled: false)
            return Output(jobs: [job], run: nil, message: "paused")
        case .resume:
            var job = try await mutateState(id: input.id, state: .scheduled, enabled: true)
            job.nextRunAt = CronScheduleParser.nextRun(after: Date(), schedule: job.schedule)
            try await store.update(job)
            return Output(jobs: [job], run: nil, message: "resumed")
        case .remove:
            let id = try input.id.unwrap(or: CronToolError.missingField("id"))
            try await store.delete(idOrName: id)
            return Output(jobs: [], run: nil, message: "removed")
        case .run:
            guard let scheduler, let executor else { throw CronToolError.schedulerUnavailable }
            let id = try input.id.unwrap(or: CronToolError.missingField("id"))
            let run = try await scheduler.runNow(idOrName: id, executor: executor)
            return Output(jobs: [], run: run, message: "ran")
        }
    }

    private func mutateState(id: String?, state: CronJobState, enabled: Bool) async throws -> CronJob {
        let id = try id.unwrap(or: CronToolError.missingField("id"))
        guard var job = try await store.get(idOrName: id) else { throw CronStoreError.notFound(id) }
        job.state = state
        job.enabled = enabled
        try await store.update(job)
        return job
    }
}

public enum CronToolError: Error, Sendable, LocalizedError {
    case missingField(String)
    case schedulerUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingField(let name): "missing field: \(name)"
        case .schedulerUnavailable: "cron scheduler is not wired into this registry"
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
