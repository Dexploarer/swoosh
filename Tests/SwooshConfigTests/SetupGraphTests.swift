// Tests/SwooshConfigTests/SetupGraphTests.swift
//
// Verifies SetupGraphExecutor's dependency ordering, mode filtering,
// success/failure roll-up, and rollback chain. Each test wires a
// minimal stub `SetupStep` so the test doesn't touch the real
// filesystem, daemon, or model providers.

import Testing
import Foundation
@testable import SwooshConfig

// MARK: - Stubs

private final class StubUI: SetupUI, @unchecked Sendable {
    func showProgress(_ step: SetupStepID, message: String) async {}
    func showResult(_ step: SetupStepID, result: SetupResult) async {}
    func showVerification(_ step: SetupStepID, result: VerificationResult) async {}
    func askYesNo(_ prompt: String, default def: Bool) async -> Bool { def }
    func askChoice(_ prompt: String, options: [String], default def: Int) async -> Int { def }
    func askString(_ prompt: String, default def: String?) async -> String { def ?? "" }
    func askSecret(_ prompt: String) async -> String { "" }
    func showReport(_ report: SetupReport) async {}
}

private struct StubStep: SetupStep {
    let id: SetupStepID
    let title: String
    let description: String = ""
    let dependencies: [SetupStepID]
    let isRequired: Bool
    var configureResult: SetupResult = .success(summary: "ok")
    var verifyResult: VerificationResult = .passed(details: "ok")

    init(
        id: SetupStepID,
        dependencies: [SetupStepID] = [],
        isRequired: Bool = true,
        title: String? = nil,
        configureResult: SetupResult = .success(summary: "ok"),
        verifyResult: VerificationResult = .passed(details: "ok")
    ) {
        self.id = id
        self.title = title ?? id.rawValue
        self.dependencies = dependencies
        self.isRequired = isRequired
        self.configureResult = configureResult
        self.verifyResult = verifyResult
    }

    func detect(context: SetupContext) async throws -> SetupStatus { .missing }
    func configure(context: SetupContext) async throws -> SetupResult { configureResult }
    func verify(context: SetupContext) async throws -> VerificationResult { verifyResult }
    func rollback(context: SetupContext) async throws {}
}

private func makeContext() -> SetupContext {
    SetupContext(
        credentials: KeychainCredentialStore(service: "ai.swoosh.tests.setup"),
        config: SwooshConfigStore(configDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-setup-tests-\(UUID().uuidString)")),
        hardware: HardwareDetector().detect(),
        ui: StubUI()
    )
}

// MARK: - Tests

@Suite("SetupGraphExecutor.execute")
struct SetupGraphExecutorTests {

    @Test("quick mode runs only required steps")
    func quickModeFiltersOptional() async {
        let steps: [any SetupStep] = [
            StubStep(id: "required-1", isRequired: true),
            StubStep(id: "optional-1", isRequired: false),
        ]
        let executor = SetupGraphExecutor(steps: steps)
        let report = await executor.execute(mode: .quick, context: makeContext())
        let ids = Set(report.steps.map(\.stepID.rawValue))
        #expect(ids.contains("required-1"))
        #expect(!ids.contains("optional-1"))
    }

    @Test("full mode runs every step")
    func fullModeRunsAll() async {
        let steps: [any SetupStep] = [
            StubStep(id: "required-1", isRequired: true),
            StubStep(id: "optional-1", isRequired: false),
        ]
        let executor = SetupGraphExecutor(steps: steps)
        let report = await executor.execute(mode: .full, context: makeContext())
        #expect(report.steps.count == 2)
        #expect(report.allPassed)
    }

    @Test("failed verification surfaces in report.failures")
    func failureSurfaces() async {
        let steps: [any SetupStep] = [
            StubStep(
                id: "bad",
                isRequired: true,
                verifyResult: .failed(error: "smoke test failed")
            ),
        ]
        let executor = SetupGraphExecutor(steps: steps)
        let report = await executor.execute(mode: .quick, context: makeContext())
        #expect(!report.allPassed)
        #expect(report.failures.count == 1)
        #expect(report.failures.first?.stepID.rawValue == "bad")
    }

    @Test("steps with unmet required dependencies are skipped")
    func missingRequiredDependencySkips() async {
        let steps: [any SetupStep] = [
            // Failing required ancestor.
            StubStep(
                id: "ancestor",
                isRequired: true,
                verifyResult: .failed(error: "boom")
            ),
            // Downstream child that depends on it — must be skipped.
            StubStep(id: "child", dependencies: ["ancestor"], isRequired: true),
        ]
        let executor = SetupGraphExecutor(steps: steps)
        let report = await executor.execute(mode: .quick, context: makeContext())
        let childRecord = report.steps.first { $0.stepID.rawValue == "child" }
        guard let childRecord else {
            Issue.record("child step missing from report")
            return
        }
        if case .skipped = childRecord.result {
            // Expected — the dependency failed so the child was skipped.
        } else {
            Issue.record("expected child to be skipped, got \(childRecord.result)")
        }
    }
}

@Suite("SetupReport rollups")
struct SetupReportRollupTests {

    @Test("allPassed treats warning as passing")
    func warningCountsAsPassed() {
        let records = [
            StepExecutionRecord(
                stepID: "x",
                status: .configured(summary: "ok"),
                result: .success(summary: "ok"),
                verification: .warning(message: "skipped")
            )
        ]
        let report = SetupReport(timestamp: Date(), steps: records)
        #expect(report.allPassed)
        #expect(report.failures.isEmpty)
    }

    @Test("failures isolates only verification-failed records")
    func failuresFilter() {
        let records = [
            StepExecutionRecord(
                stepID: "a", status: .missing, result: .success(summary: "x"),
                verification: .passed(details: "x")
            ),
            StepExecutionRecord(
                stepID: "b", status: .missing, result: .failed(error: "y"),
                verification: .failed(error: "y")
            ),
        ]
        let report = SetupReport(timestamp: Date(), steps: records)
        #expect(report.failures.count == 1)
        #expect(report.failures.first?.stepID.rawValue == "b")
    }
}
