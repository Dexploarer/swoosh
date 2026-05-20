// SwooshCron/CronScheduler.swift — Due-job detection and execution
import Foundation
import SwooshTools

public actor CronScheduler {
    private let store: FileCronJobStore
    private let processRunner: any ProcessRunning
    private var ticking = false

    public init(store: FileCronJobStore, processRunner: any ProcessRunning) {
        self.store = store
        self.processRunner = processRunner
    }

    @discardableResult
    public func tick(now: Date = Date(), executor: CronAgentExecutor) async throws -> [CronRunRecord] {
        guard !ticking else { return [] }
        ticking = true
        defer { ticking = false }
        let due = try await store.list().filter { job in
            job.enabled && job.state == .scheduled && (job.nextRunAt ?? .distantFuture) <= now
        }
        var records: [CronRunRecord] = []
        for job in due {
            let record = try await run(job: job, now: now, executor: executor)
            records.append(record)
        }
        return records
    }

    public func runNow(idOrName: String, executor: CronAgentExecutor) async throws -> CronRunRecord {
        guard let job = try await store.get(idOrName: idOrName) else { throw CronStoreError.notFound(idOrName) }
        return try await run(job: job, now: Date(), executor: executor)
    }

    private func run(job: CronJob, now: Date, executor: CronAgentExecutor) async throws -> CronRunRecord {
        var running = job
        running.state = .running
        try await store.update(running)

        let started = Date()
        let sessionID = "cron-\(job.id)-\(Int(started.timeIntervalSince1970))"
        do {
            let scriptOutput = try await runScriptIfNeeded(job: job)
            if scriptOutput.wakeAgent == false {
                let record = try await finish(job: job, started: started, status: .skipped, output: scriptOutput.contextText, error: nil, now: now)
                return record
            }
            if job.noAgent {
                return try await finish(job: job, started: started, status: .ok, output: scriptOutput.contextText, error: nil, now: now)
            }
            let prompt = try await buildPrompt(job: job, scriptContext: scriptOutput.contextText)
            let output = try await executor(CronExecutionRequest(
                job: job,
                sessionID: sessionID,
                prompt: prompt,
                workdir: job.workdir.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) },
                skills: job.skills,
                enabledToolsets: job.enabledToolsets
            ))
            return try await finish(job: job, started: started, status: .ok, output: output, error: nil, now: now)
        } catch {
            return try await finish(job: job, started: started, status: .failed, output: nil, error: error, now: now)
        }
    }

    private func runScriptIfNeeded(job: CronJob) async throws -> CronScriptOutput {
        guard let script = job.script, !script.isEmpty else { return CronScriptOutput(wakeAgent: true, contextText: nil) }
        let workdir = job.workdir.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
        let executable: String
        let arguments: [String]
        if script.hasSuffix(".py") {
            executable = "/usr/bin/env"
            arguments = ["python3", script]
        } else if script.hasSuffix(".sh") {
            executable = "/bin/sh"
            arguments = [script]
        } else {
            executable = "/bin/sh"
            arguments = ["-lc", script]
        }
        let result = try await processRunner.run(executable: executable, arguments: arguments, workingDirectory: workdir, environment: nil)
        guard result.exitCode == 0 else {
            throw CronExecutionError.scriptFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return parseScriptOutput(result.stdout)
    }

    private func parseScriptOutput(_ stdout: String) -> CronScriptOutput {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let gateIndex = lines.indices.reversed().first(where: { !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return CronScriptOutput(wakeAgent: true, contextText: stdout.isEmpty ? nil : stdout)
        }
        let last = lines[gateIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard last.hasPrefix("{"),
              let data = last.data(using: .utf8),
              let gate = try? JSONDecoder().decode(CronWakeGate.self, from: data)
        else {
            return CronScriptOutput(wakeAgent: true, contextText: stdout.isEmpty ? nil : stdout)
        }
        let prefix = lines[..<gateIndex].joined(separator: "\n")
        let context = gate.context.map { json in
            let encoded = (try? JSONEncoder.swooshCron.encode(json)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return [prefix, encoded].filter { !$0.isEmpty }.joined(separator: "\n")
        } ?? (prefix.isEmpty ? nil : prefix)
        return CronScriptOutput(wakeAgent: gate.wakeAgent, contextText: context)
    }

    private func buildPrompt(job: CronJob, scriptContext: String?) async throws -> String {
        var sections: [String] = []
        if !job.contextFrom.isEmpty {
            var upstream: [String] = []
            for id in job.contextFrom {
                if let output = try await store.latestSuccessfulOutput(jobIDOrName: id) {
                    upstream.append("## \(id)\n\(output)")
                }
            }
            if !upstream.isEmpty { sections.append("# Upstream Context\n\(upstream.joined(separator: "\n\n"))") }
        }
        if let scriptContext, !scriptContext.isEmpty {
            sections.append("# Script Context\n\(scriptContext)")
        }
        sections.append("# Task\n\(job.prompt)")
        return sections.joined(separator: "\n\n")
    }

    private func finish(
        job: CronJob,
        started: Date,
        status: CronRunStatus,
        output: String?,
        error: Error?,
        now: Date
    ) async throws -> CronRunRecord {
        let finished = Date()
        var updated = job
        updated.state = nextState(for: job, status: status)
        updated.completedRuns += status == .ok ? 1 : 0
        updated.lastRunAt = finished
        updated.lastStatus = status
        updated.nextRunAt = updated.state == .completed ? nil : CronScheduleParser.nextRun(after: now, schedule: job.schedule)
        let body = output ?? error?.localizedDescription ?? ""
        let outputURL = try await store.outputPath(jobID: job.id, date: finished)
        try body.write(to: outputURL, atomically: true, encoding: .utf8)
        let record = CronRunRecord(jobID: job.id, startedAt: started, finishedAt: finished, status: status, outputPath: outputURL.path, summary: String(body.prefix(500)))
        try await store.update(updated)
        try await store.saveRun(record)
        return record
    }

    private func nextState(for job: CronJob, status: CronRunStatus) -> CronJobState {
        if let repeatLimit = job.repeatLimit, job.completedRuns + (status == .ok ? 1 : 0) >= repeatLimit {
            return .completed
        }
        if job.schedule.kind == .once {
            return .completed
        }
        return status == .failed ? .failed : .scheduled
    }
}

private struct CronScriptOutput: Sendable {
    let wakeAgent: Bool?
    let contextText: String?
}

private struct CronWakeGate: Decodable {
    let wakeAgent: Bool?
    let context: SwooshTools.JSONValue?

    enum CodingKeys: String, CodingKey {
        case wakeAgent
        case wakeAgentLegacy = "wake_agent"
        case context
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.wakeAgent = (try? c.decode(Bool.self, forKey: .wakeAgent)) ?? (try? c.decode(Bool.self, forKey: .wakeAgentLegacy))
        self.context = try? c.decode(SwooshTools.JSONValue.self, forKey: .context)
    }
}

public enum CronExecutionError: Error, Sendable, LocalizedError {
    case scriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): "cron script failed: \(message)"
        }
    }
}
