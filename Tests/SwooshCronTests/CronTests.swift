// Tests/SwooshCronTests/CronTests.swift — 0.5A SwooshCron behavioural suite
//
// Covers: schedule parsing branches, file-store CRUD round-trip,
// scheduler tick + skip + reentry guard, CronJobTool actions, and
// CronProcessRunner allowlist/timeout/policy. Each test stands alone;
// the store is sandboxed to a fresh temp directory per case so we never
// touch ~/.swoosh/cron.

import Foundation
import Testing
@testable import SwooshCron
@testable import SwooshTools

private actor PromptCollector {
    private(set) var captured: String = ""
    func record(_ value: String) { captured = value }
}

private struct StubProcessRunner: ProcessRunning {
    let stdout: String
    let exitCode: Int32
    let stderr: String
    init(stdout: String = "", exitCode: Int32 = 0, stderr: String = "") {
        self.stdout = stdout
        self.exitCode = exitCode
        self.stderr = stderr
    }
    func run(executable: String, arguments: [String], workingDirectory: URL?, environment: [String: String]?) async throws -> ProcessResult {
        ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }
}

private func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("swoosh-cron-tests-\(UUID().uuidString)", isDirectory: true)
}

private func makeJob(
    name: String = "test-job",
    prompt: String = "do the thing",
    schedule: CronSchedule = CronSchedule(kind: .interval, expression: "60"),
    script: String? = nil,
    noAgent: Bool = false,
    contextFrom: [String] = []
) -> CronJob {
    CronJob(
        name: name,
        prompt: prompt,
        schedule: schedule,
        script: script,
        noAgent: noAgent,
        contextFrom: contextFrom
    )
}

// MARK: - Schedule parsing

@Suite("CronScheduleParser")
struct CronScheduleParserTests {

    @Test("Parses interval `every 30m`")
    func parsesIntervalMinutes() throws {
        let schedule = try CronScheduleParser.parse("every 30m")
        #expect(schedule.kind == .interval)
        #expect(schedule.expression == "1800")
    }

    @Test("Parses interval `every 2h`")
    func parsesIntervalHours() throws {
        let schedule = try CronScheduleParser.parse("every 2h")
        #expect(schedule.kind == .interval)
        #expect(schedule.expression == "7200")
    }

    @Test("Parses `daily` schedule with default clock")
    func parsesDailyDefault() throws {
        let schedule = try CronScheduleParser.parse("daily")
        #expect(schedule.kind == .daily)
        #expect(schedule.expression == "09:00")
    }

    @Test("Parses `daily at 7pm` clock time")
    func parsesDailyClockTime() throws {
        let schedule = try CronScheduleParser.parse("daily at 7pm")
        #expect(schedule.kind == .daily)
        #expect(schedule.expression == "19:00")
    }

    @Test("Parses `every Monday at 10am` weekly schedule")
    func parsesWeekly() throws {
        let schedule = try CronScheduleParser.parse("every monday at 10am")
        #expect(schedule.kind == .weekly)
        #expect(schedule.expression == "2 10:00")
    }

    @Test("Parses `in 5m` one-shot")
    func parsesOnceInDuration() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = try CronScheduleParser.parse("in 5m", now: now)
        #expect(schedule.kind == .once)
        let parsed = ISO8601DateFormatter().date(from: schedule.expression)
        #expect(parsed?.timeIntervalSince(now) == 300)
    }

    @Test("Parses 5-field cron expression")
    func parsesCronExpression() throws {
        let schedule = try CronScheduleParser.parse("0 9 * * *")
        #expect(schedule.kind == .cron)
        #expect(schedule.expression == "0 9 * * *")
    }

    @Test("Unsupported input throws")
    func unsupportedThrows() {
        #expect(throws: CronScheduleError.self) {
            _ = try CronScheduleParser.parse("at no specific time")
        }
    }

    @Test("nextRun honors interval seconds")
    func nextRunInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = CronSchedule(kind: .interval, expression: "300")
        let next = CronScheduleParser.nextRun(after: now, schedule: schedule)
        #expect(next?.timeIntervalSince(now) == 300)
    }

    @Test("nextRun returns nil for malformed interval")
    func nextRunIntervalMalformed() {
        let schedule = CronSchedule(kind: .interval, expression: "not-a-number")
        #expect(CronScheduleParser.nextRun(after: Date(), schedule: schedule) == nil)
    }
}

// MARK: - File store

@Suite("FileCronJobStore")
struct FileCronJobStoreTests {

    @Test("Save then list round-trips through disk")
    func saveAndListPersists() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let job = makeJob(name: "alpha")
        try await store.save(job)

        let reloaded = FileCronJobStore(root: root)
        let listed = try await reloaded.list()
        #expect(listed.count == 1)
        #expect(listed.first?.name == "alpha")
    }

    @Test("get by id and get by name both resolve")
    func getByIdAndByName() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let job = makeJob(name: "named-job")
        try await store.save(job)
        #expect(try await store.get(idOrName: job.id)?.name == "named-job")
        #expect(try await store.get(idOrName: "named-job")?.id == job.id)
        #expect(try await store.get(idOrName: "missing") == nil)
    }

    @Test("update of unknown id throws notFound")
    func updateUnknownThrows() async {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let job = makeJob()
        await #expect(throws: CronStoreError.self) {
            try await store.update(job)
        }
    }

    @Test("delete removes by id")
    func deleteByID() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let job = makeJob()
        try await store.save(job)
        try await store.delete(idOrName: job.id)
        #expect(try await store.list().isEmpty)
    }

    @Test("listRuns returns most-recent first and respects limit")
    func listRunsOrderingAndLimit() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let job = makeJob()
        try await store.save(job)
        let early = CronRunRecord(jobID: job.id, startedAt: Date(timeIntervalSince1970: 1000), finishedAt: Date(timeIntervalSince1970: 1010), status: .ok, outputPath: nil, summary: "early")
        let late = CronRunRecord(jobID: job.id, startedAt: Date(timeIntervalSince1970: 2000), finishedAt: Date(timeIntervalSince1970: 2010), status: .ok, outputPath: nil, summary: "late")
        try await store.saveRun(early)
        try await store.saveRun(late)
        let ordered = try await store.listRuns(jobID: job.id, limit: nil)
        #expect(ordered.first?.summary == "late")
        let limited = try await store.listRuns(jobID: job.id, limit: 1)
        #expect(limited.count == 1)
        #expect(limited.first?.summary == "late")
    }

    @Test("latestSuccessfulOutput reads back saved file")
    func latestSuccessfulOutputReadsFile() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let job = makeJob(name: "upstream")
        try await store.save(job)
        let outputURL = try await store.outputPath(jobID: job.id, date: Date(timeIntervalSince1970: 1_700_000_500))
        try "the-output".write(to: outputURL, atomically: true, encoding: .utf8)
        let run = CronRunRecord(jobID: job.id, startedAt: Date(timeIntervalSince1970: 1_700_000_000), finishedAt: Date(timeIntervalSince1970: 1_700_000_500), status: .ok, outputPath: outputURL.path, summary: "ok")
        try await store.saveRun(run)
        #expect(try await store.latestSuccessfulOutput(jobIDOrName: "upstream") == "the-output")
    }
}

// MARK: - Scheduler

@Suite("CronScheduler")
struct CronSchedulerTests {

    @Test("tick fires due jobs and updates state")
    func tickFiresDueJobs() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(store: store, processRunner: StubProcessRunner())
        var job = makeJob(name: "due-now")
        job.nextRunAt = Date(timeIntervalSince1970: 0) // in the past
        try await store.save(job)

        let collector = PromptCollector()
        let records = try await scheduler.tick(now: Date()) { request in
            await collector.record(request.prompt)
            return "agent-output"
        }
        #expect(records.count == 1)
        #expect(records.first?.status == .ok)
        let captured = await collector.captured
        #expect(captured.contains("do the thing"))
        let after = try await store.get(idOrName: job.id)
        #expect(after?.state == .scheduled) // interval re-arms
        #expect(after?.completedRuns == 1)
    }

    @Test("tick skips jobs that aren't yet due")
    func tickSkipsFutureJobs() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(store: store, processRunner: StubProcessRunner())
        var job = makeJob(name: "future")
        job.nextRunAt = Date(timeIntervalSinceNow: 3600)
        try await store.save(job)

        let records = try await scheduler.tick(now: Date()) { _ in
            Issue.record("executor should not run")
            return "unexpected"
        }
        #expect(records.isEmpty)
    }

    @Test("tick skips disabled jobs")
    func tickSkipsDisabledJobs() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(store: store, processRunner: StubProcessRunner())
        var job = makeJob(name: "paused")
        job.nextRunAt = Date(timeIntervalSince1970: 0)
        job.enabled = false
        job.state = .paused
        try await store.save(job)

        let records = try await scheduler.tick(now: Date()) { _ in "unexpected" }
        #expect(records.isEmpty)
    }

    @Test("once-kind schedule completes after a single run")
    func onceCompletesAfterRun() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(store: store, processRunner: StubProcessRunner())
        var job = makeJob(
            name: "one-shot",
            schedule: CronSchedule(kind: .once, expression: ISO8601DateFormatter().string(from: Date()))
        )
        job.nextRunAt = Date(timeIntervalSince1970: 0)
        try await store.save(job)

        _ = try await scheduler.tick(now: Date()) { _ in "ok" }
        let after = try await store.get(idOrName: job.id)
        #expect(after?.state == .completed)
        #expect(after?.nextRunAt == nil)
    }

    @Test("noAgent script still reports ok without invoking executor")
    func noAgentJobSucceedsWithoutExecutor() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(
            store: store,
            processRunner: StubProcessRunner(stdout: "script-said-hi\n")
        )
        let job = makeJob(name: "script-only", script: "poll.sh", noAgent: true)
        try await store.save(job)

        let run = try await scheduler.runNow(idOrName: job.id) { _ in
            Issue.record("executor should not run when noAgent")
            return "unexpected"
        }
        #expect(run.status == .ok)
    }

    @Test("wakeAgent false skips agent executor (legacy snake_case key)")
    func wakeAgentLegacyKeySkipsAgent() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(
            store: store,
            processRunner: StubProcessRunner(stdout: "{\"wake_agent\": false}\n")
        )
        let job = makeJob(name: "legacy-gate", script: "poll.sh")
        try await store.save(job)
        let run = try await scheduler.runNow(idOrName: job.id) { _ in
            Issue.record("executor should not run when gate denies")
            return "unexpected"
        }
        #expect(run.status == .skipped)
    }
}

// MARK: - CronJobTool

@Suite("CronJobTool")
struct CronJobToolTests {

    private func context() -> ToolContext { ToolContext(sessionID: "cron-tool-tests") }

    private func tool(scheduler: CronScheduler? = nil, executor: CronAgentExecutor? = nil) -> (CronJobTool, FileCronJobStore, URL) {
        let root = tempRoot()
        let store = FileCronJobStore(root: root)
        let tool = CronJobTool(dependencies: CronToolDependencies(store: store, scheduler: scheduler, executor: executor))
        return (tool, store, root)
    }

    @Test("create then list returns the job")
    func createThenList() async throws {
        let (tool, _, root) = tool()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await tool.call(.init(action: .create, name: "alpha", schedule: "every 5m", prompt: "summarize"), context: context())
        #expect(created.jobs.count == 1)
        #expect(created.jobs.first?.name == "alpha")
        let listed = try await tool.call(.init(action: .list), context: context())
        #expect(listed.jobs.count == 1)
    }

    @Test("create without prompt throws missingField")
    func createWithoutPromptThrows() async {
        let (tool, _, root) = tool()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: CronToolError.self) {
            _ = try await tool.call(.init(action: .create, name: "broken", schedule: "every 5m"), context: context())
        }
    }

    @Test("update changes prompt and schedule")
    func updateChangesFields() async throws {
        let (tool, _, root) = tool()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await tool.call(.init(action: .create, name: "u", schedule: "every 5m", prompt: "v1"), context: context())
        let id = created.jobs.first!.id
        let updated = try await tool.call(.init(action: .update, id: id, schedule: "every 10m", prompt: "v2"), context: context())
        #expect(updated.jobs.first?.prompt == "v2")
        #expect(updated.jobs.first?.schedule.expression == "600")
    }

    @Test("pause then resume toggles state and re-arms nextRunAt")
    func pauseResumeToggles() async throws {
        let (tool, _, root) = tool()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await tool.call(.init(action: .create, name: "p", schedule: "every 5m", prompt: "x"), context: context())
        let id = created.jobs.first!.id
        let paused = try await tool.call(.init(action: .pause, id: id), context: context())
        #expect(paused.jobs.first?.state == .paused)
        #expect(paused.jobs.first?.enabled == false)
        let resumed = try await tool.call(.init(action: .resume, id: id), context: context())
        #expect(resumed.jobs.first?.state == .scheduled)
        #expect(resumed.jobs.first?.enabled == true)
        #expect(resumed.jobs.first?.nextRunAt != nil)
    }

    @Test("remove deletes the job")
    func removeDeletesJob() async throws {
        let (tool, store, root) = tool()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await tool.call(.init(action: .create, name: "r", schedule: "every 5m", prompt: "x"), context: context())
        _ = try await tool.call(.init(action: .remove, id: created.jobs.first!.id), context: context())
        #expect(try await store.list().isEmpty)
    }

    @Test("run without a wired scheduler throws schedulerUnavailable")
    func runWithoutSchedulerThrows() async throws {
        let (tool, _, root) = tool()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await tool.call(.init(action: .create, name: "x", schedule: "every 5m", prompt: "p"), context: context())
        await #expect(throws: CronToolError.self) {
            _ = try await tool.call(.init(action: .run, id: created.jobs.first!.id), context: context())
        }
    }

    @Test("run with scheduler returns a run record")
    func runWithSchedulerReturnsRecord() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(store: store, processRunner: StubProcessRunner())
        let executor: CronAgentExecutor = { _ in "agent-output" }
        let tool = CronJobTool(dependencies: CronToolDependencies(store: store, scheduler: scheduler, executor: executor))
        let created = try await tool.call(.init(action: .create, name: "r", schedule: "every 5m", prompt: "go"), context: ToolContext(sessionID: "t"))
        let ran = try await tool.call(.init(action: .run, id: created.jobs.first!.id), context: ToolContext(sessionID: "t"))
        #expect(ran.run?.status == .ok)
    }
}

// MARK: - CronProcessRunner

@Suite("CronProcessRunner")
struct CronProcessRunnerTests {

    @Test("Executes allowlisted shell script")
    func executesAllowlisted() async throws {
        let runner = CronProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf ok"],
            workingDirectory: FileManager.default.temporaryDirectory,
            environment: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "ok")
    }

    @Test("Blocks `sudo` executable")
    func blocksSudo() async {
        let runner = CronProcessRunner()
        await #expect(throws: CronProcessError.self) {
            _ = try await runner.run(
                executable: "/usr/bin/sudo",
                arguments: ["true"],
                workingDirectory: nil,
                environment: nil
            )
        }
    }

    @Test("Rejects missing working directory")
    func rejectsMissingWorkingDirectory() async {
        let runner = CronProcessRunner()
        await #expect(throws: CronProcessError.self) {
            _ = try await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "true"],
                workingDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                environment: nil
            )
        }
    }

    @Test("Scrubs secret-shaped env vars before exec")
    func scrubsSecretEnv() async throws {
        let runner = CronProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf \"%s\" \"${OPENAI_API_KEY-unset}\""],
            workingDirectory: FileManager.default.temporaryDirectory,
            environment: nil
        )
        #expect(result.stdout == "unset")
    }

    @Test("Fires timeout on a long-running child and does not block the cooperative pool")
    func timeoutFiresAndDoesNotBlock() async throws {
        let policy = CronProcessPolicy(timeoutSeconds: 1)
        let runner = CronProcessRunner(policy: policy)
        // Run two children concurrently — if `run` blocked the cooperative
        // pool the way it used to, this would serialize and take ~2s. With
        // the continuation-based fix they overlap.
        let start = Date()
        async let a: Void = expectTimeout(runner: runner)
        async let b: Void = expectTimeout(runner: runner)
        _ = try await (a, b)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.8, "expected concurrent timeouts (<1.8s), got \(elapsed)s")
    }

    private func expectTimeout(runner: CronProcessRunner) async throws {
        await #expect(throws: CronProcessError.self) {
            _ = try await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 5"],
                workingDirectory: FileManager.default.temporaryDirectory,
                environment: nil
            )
        }
    }
}
