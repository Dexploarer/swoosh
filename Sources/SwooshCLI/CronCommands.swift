// SwooshCLI/CronCommands.swift — Scheduled task UX
import ArgumentParser
import Foundation
import SwooshCron
import SwooshKit

struct CronCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cron",
        abstract: "Create and run scheduled agent jobs.",
        subcommands: [
            CronListCommand.self,
            CronCreateCommand.self,
            CronPauseCommand.self,
            CronResumeCommand.self,
            CronRunCommand.self,
            CronRemoveCommand.self,
        ],
        defaultSubcommand: CronListCommand.self
    )
}

struct CronListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List scheduled jobs.")

    @Flag(name: .long, help: "Output JSON.")
    var json = false

    func run() async throws {
        let jobs = try await cronStore().list()
        if json {
            let data = try JSONEncoder.swooshCLI.encode(jobs)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }
        for job in jobs {
            let next = job.nextRunAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
            print("\(job.id.padding(toLength: 14, withPad: " ", startingAt: 0)) \(job.state.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(next) \(job.name)")
        }
    }
}

struct CronCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a scheduled job.")

    @Option(name: .long, help: "Human-readable job name.")
    var name: String?

    @Option(name: .long, help: "Schedule, for example 'every 30m', 'daily at 9:00', or a five-field cron expression.")
    var schedule: String

    @Option(name: .long, help: "Agent prompt to run when due.")
    var prompt: String

    @Option(name: .long, help: "Optional shell script or shell command to run before the agent wakes.")
    var script: String?

    @Flag(name: .long, help: "Run only the script and skip the agent.")
    var noAgent = false

    @Option(name: .long, help: "Working directory for script execution.")
    var workdir: String?

    @Option(name: .long, help: "Optional delivery target label.")
    var deliver: String?

    @Option(name: .long, help: "Stop after this many successful runs.")
    var repeatLimit: Int?

    func run() async throws {
        let job = try CronJob(
            name: name ?? String(prompt.prefix(48)),
            prompt: prompt,
            schedule: CronScheduleParser.parse(schedule),
            deliver: deliver,
            repeatLimit: repeatLimit,
            script: script,
            noAgent: noAgent,
            workdir: workdir
        )
        try await cronStore().save(job)
        print("Created \(job.id) — \(job.name)")
    }
}

struct CronPauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pause", abstract: "Pause a scheduled job.")

    @Argument(help: "Job id or name.")
    var id: String

    func run() async throws {
        let store = cronStore()
        guard var job = try await store.get(idOrName: id) else { throw ValidationError("Job not found: \(id)") }
        job.enabled = false
        job.state = .paused
        try await store.update(job)
        print("Paused \(job.id).")
    }
}

struct CronResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "resume", abstract: "Resume a scheduled job.")

    @Argument(help: "Job id or name.")
    var id: String

    func run() async throws {
        let store = cronStore()
        guard var job = try await store.get(idOrName: id) else { throw ValidationError("Job not found: \(id)") }
        job.enabled = true
        job.state = .scheduled
        job.nextRunAt = CronScheduleParser.nextRun(after: Date(), schedule: job.schedule)
        try await store.update(job)
        print("Resumed \(job.id).")
    }
}

struct CronRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Run a job immediately.")

    @Argument(help: "Job id or name.")
    var id: String

    func run() async throws {
        let swoosh = try await Swoosh.configure { _ in }
        let scheduler = CronScheduler(store: cronStore(), processRunner: CronProcessRunner())
        let record = try await scheduler.runNow(idOrName: id) { request in
            let response = try await swoosh.kernel.run(AgentRequest(sessionID: request.sessionID, input: request.prompt))
            return response.message
        }
        print("\(record.status.rawValue): \(record.summary)")
        if let outputPath = record.outputPath {
            print(outputPath)
        }
    }
}

struct CronRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a scheduled job.")

    @Argument(help: "Job id or name.")
    var id: String

    func run() async throws {
        try await cronStore().delete(idOrName: id)
        print("Removed \(id).")
    }
}

private func cronStore() -> FileCronJobStore {
    FileCronJobStore()
}
