// Tests/SwooshCLITests/SetupCommissioningTests.swift — Commissioning runtime — 0.4A
//
// Covers the runtime helpers split out of SetupCommands.swift into
// SetupCommissioning.swift. These don't exercise the daemon-launch path
// (that involves spawning processes); they cover the Codable surface,
// the SetupModelPath argument shape, and the on-disk report writer.

import Testing
import Foundation
import SwooshClient
import SwooshConfig
@testable import SwooshCLI

@Suite("SetupModelPath")
struct SetupModelPathTests {
    @Test("SetupModelPath covers local/cloud/hybrid")
    func cases() {
        #expect(Set(SetupModelPath.allCases.map(\.rawValue)) == ["local", "cloud", "hybrid"])
    }

    @Test("SetupModelPath parses via ExpressibleByArgument")
    func argumentParsing() throws {
        #expect(SetupModelPath(argument: "local") == .local)
        #expect(SetupModelPath(argument: "cloud") == .cloud)
        #expect(SetupModelPath(argument: "hybrid") == .hybrid)
        #expect(SetupModelPath(argument: "garbage") == nil)
    }

    @Test("SetupModelPath JSON round-trips")
    func codableRoundTrip() throws {
        for path in SetupModelPath.allCases {
            let data = try JSONEncoder().encode(path)
            let decoded = try JSONDecoder().decode(SetupModelPath.self, from: data)
            #expect(decoded == path)
        }
    }
}

@Suite("SetupCommissioningReport")
struct SetupCommissioningReportTests {
    @Test("SetupCommissioningReport round-trips through swooshCLI encoder")
    func reportRoundTrip() throws {
        let report = SetupCommissioningReport(
            date: "2026-05-23T00:00:00Z",
            mode: "quick",
            profile: "developer",
            modelPath: "hybrid",
            cpu: "Apple M2",
            memoryGB: 16,
            appleSilicon: true,
            commissioning: SetupCommissioningResult(
                configPath: "/tmp/swoosh/config.json",
                apiTokenPath: "/tmp/swoosh/api_token",
                stateDirectories: ["/tmp/swoosh", "/tmp/swoosh/logs"],
                checks: [
                    CommissioningCheck(name: "Config", passed: true, detail: "/tmp/swoosh/config.json"),
                    CommissioningCheck(name: "API token", passed: true, detail: "/tmp/swoosh/api_token"),
                ],
                readiness: SwooshReadinessReport(
                    state: .ready,
                    summary: "ready",
                    components: []
                )
            ),
            scoutSummary: nil,
            nextSteps: setupNextSteps
        )

        let encoded = try JSONEncoder.swooshCLI.encode(report)
        // `swooshCLI` encodes Dates as ISO-8601 strings; round-trip with a
        // matching decoder so `generatedAt` on the readiness report decodes
        // cleanly.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SetupCommissioningReport.self, from: encoded)
        #expect(decoded.date == report.date)
        #expect(decoded.mode == "quick")
        #expect(decoded.profile == "developer")
        #expect(decoded.commissioning.checks.count == 2)
        #expect(decoded.nextSteps == setupNextSteps)
    }

    @Test("setupNextSteps lists the curated post-setup commands")
    func nextStepsShape() {
        #expect(setupNextSteps.contains("swoosh doctor"))
        #expect(setupNextSteps.contains("swoosh scout run --depth recommended"))
        #expect(setupNextSteps.contains("swoosh memory list"))
        #expect(setupNextSteps.contains("swoosh memory approve --all"))
    }
}

@Suite("writeSetupReport on disk")
struct WriteSetupReportTests {
    @Test("writeSetupReport writes a JSON file under setupReportsDir")
    func writesReport() async throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwooshCLITests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let config = SwooshConfigStore(configDirectory: tempBase)
        try config.ensureDirectories()

        // HardwareProfile has no public memberwise init — use the real
        // detector for the test (cheap; no network, no model load).
        let hardware = HardwareDetector().detect()
        let result = SetupCommissioningResult(
            configPath: config.configFile.path,
            apiTokenPath: config.apiTokenFile.path,
            stateDirectories: config.requiredStateDirectories.map(\.path),
            checks: [],
            readiness: SwooshReadinessReport(state: .ready, summary: "ok", components: [])
        )
        let ctx = CommissioningContext(
            config: config,
            hardware: hardware,
            profile: .developer,
            modelPath: .hybrid,
            mode: "quick",
            daemonHost: "127.0.0.1",
            daemonPort: 8787,
            daemonStartTimeout: 1
        )
        let reportPath = try writeSetupReport(
            ctx,
            commissioning: result,
            scoutSummary: nil,
            nextSteps: setupNextSteps
        )

        #expect(FileManager.default.fileExists(atPath: reportPath.path))
        let raw = try Data(contentsOf: reportPath)
        let decoded = try JSONDecoder().decode(SetupCommissioningReport.self, from: raw)
        #expect(decoded.mode == "quick")
        #expect(decoded.profile == "developer")
        #expect(decoded.modelPath == "hybrid")
    }
}

@Suite("makeSwooshConfigStore resolves ~ and relative paths")
struct ConfigPathOptionsTests {
    @Test("nil configDirectory yields the default ~/.swoosh store")
    func defaultsToHome() {
        let store = makeSwooshConfigStore(configDirectory: nil)
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
            .standardizedFileURL
        #expect(store.configDirectory.standardizedFileURL == home)
    }

    @Test("Absolute path is honoured verbatim")
    func absolutePath() {
        let store = makeSwooshConfigStore(configDirectory: "/tmp/swooshcli-test-abs")
        #expect(store.configDirectory.path == "/tmp/swooshcli-test-abs")
    }

    @Test("Tilde expansion produces a home-rooted URL")
    func tildeExpansion() {
        let store = makeSwooshConfigStore(configDirectory: "~/swooshcli-test-tilde")
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("swooshcli-test-tilde")
            .standardizedFileURL
        #expect(store.configDirectory.standardizedFileURL == expected)
    }
}
