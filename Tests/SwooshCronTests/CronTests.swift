import Foundation
import Testing
@testable import SwooshCron
@testable import SwooshTools

private struct StubProcessRunner: ProcessRunning {
    let stdout: String
    init(stdout: String = "") { self.stdout = stdout }
    func run(executable: String, arguments: [String], workingDirectory: URL?, environment: [String: String]?) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: stdout, stderr: "")
    }
}

@Suite("Cron")
struct CronTests {
    @Test("Parses interval schedules")
    func parsesInterval() throws {
        let schedule = try CronScheduleParser.parse("every 30m")
        #expect(schedule.kind == .interval)
        #expect(schedule.expression == "1800")
    }

    @Test("wakeAgent false skips agent executor")
    func wakeAgentFalseSkipsAgent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileCronJobStore(root: root)
        let scheduler = CronScheduler(
            store: store,
            processRunner: StubProcessRunner(stdout: "{\"wakeAgent\": false}\n")
        )
        let job = CronJob(
            name: "poll",
            prompt: "Summarize changes",
            schedule: CronSchedule(kind: .interval, expression: "60"),
            script: "poll.sh"
        )
        try await store.save(job)
        let run = try await scheduler.runNow(idOrName: job.id) { _ in
            Issue.record("executor should not run")
            return "unexpected"
        }
        #expect(run.status == .skipped)
    }

    @Test("Cron process runner executes allowlisted scripts")
    func processRunnerExecutesAllowlistedScript() async throws {
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

    @Test("Cron process runner blocks disallowed executables")
    func processRunnerBlocksDisallowedExecutable() async {
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

    @Test("Cron process runner validates working directory")
    func processRunnerValidatesWorkingDirectory() async {
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
}
