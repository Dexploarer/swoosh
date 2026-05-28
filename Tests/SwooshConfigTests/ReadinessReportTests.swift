// Tests/SwooshConfigTests/ReadinessReportTests.swift — 0.1A
//
// Exercises the readiness COMPUTATION (`SwooshReadinessDetector.report`),
// distinct from RuntimeReadinessTests which pins the SwooshRuntimeConfig
// struct. Confirms the "daemon startup → readiness check passes" path:
// healthy daemon inputs yield a ready daemon-chat component and the report
// computes without error; an unreachable daemon degrades rather than
// crashes. Uses a throwaway config dir so it never reads real ~/.swoosh.

import Testing
import Foundation
@testable import SwooshConfig
import SwooshClient

@Suite("SwooshReadinessDetector.report")
struct ReadinessReportTests {

    private func tempDetector() throws -> SwooshReadinessDetector {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SwooshReadinessDetector(config: SwooshConfigStore(configDirectory: dir))
    }

    private func daemonChat(_ report: SwooshReadinessReport) -> SwooshReadinessComponent? {
        report.components.first { $0.id == "daemon.chat" }
    }

    @Test("Healthy daemon inputs → daemon-chat ready, report computes")
    func healthyDaemonReady() throws {
        let report = try tempDetector().report(inputs: SwooshReadinessInputs(
            daemonReachable: true, chatEnabled: true,
            activeProviderName: "OpenAI", activeModel: "gpt-5", promptableSkillCount: 3
        ))
        #expect(!report.components.isEmpty)
        #expect(daemonChat(report)?.status == .ready)
        #expect(!report.summary.isEmpty)
    }

    @Test("Unreachable daemon → daemon-chat not ready, report still produced (no crash)")
    func unreachableDegradesNotCrashes() throws {
        let report = try tempDetector().report(inputs: SwooshReadinessInputs(
            daemonReachable: false, chatEnabled: false
        ))
        #expect(daemonChat(report)?.status != .ready)
        #expect([.degraded, .blocked].contains(report.state))
    }

    @Test("Empty inputs compute a report without error")
    func emptyInputs() throws {
        let report = try tempDetector().report()
        #expect(!report.components.isEmpty)
        // State is one of the three legal values — the point is it doesn't trap.
        #expect([.ready, .degraded, .blocked].contains(report.state))
    }
}
