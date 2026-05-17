// Tests/SwooshFlowTests/WorkflowReplayTests.swift — 0.5C Tests

import Testing
import Foundation
@testable import SwooshFlow
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Mock tool executor
// ═══════════════════════════════════════════════════════════════

final class MockToolExecutor: WorkflowToolExecuting, @unchecked Sendable {
    var executedTools: [String] = []
    var descriptors: [String: ToolDescriptor] = [:]
    var results: [String: ToolExecutionResult] = [:]

    func execute(toolName: String, arguments: JSONValue, origin: ToolCallOrigin, sessionID: String) async throws -> ToolExecutionResult {
        executedTools.append(toolName)
        if let r = results[toolName] { return r }
        return ToolExecutionResult(requestID: "r", toolName: toolName, status: .succeeded, output: .string("ok"))
    }
    func getDescriptor(toolName: String) async -> ToolDescriptor? { descriptors[toolName] }
}

func readOnlyDescriptor(_ name: String) -> ToolDescriptor {
    ToolDescriptor(id: name, name: name, displayName: name, description: "",
        inputSchema: JSONSchema(type: "object"), outputSchema: JSONSchema(type: "object"),
        permission: .fileRead, risk: .readOnly, approval: .never, toolset: .core)
}

func makeDraftForReplay(steps: [WorkflowStep05A]? = nil) -> WorkflowDraft05A {
    WorkflowDraft05A(id: "rd", name: "Test Replay", summary: "t",
        steps: steps ?? [
            WorkflowStep05A(index: 1, title: "List", kind: .toolCall, toolName: "file.list"),
            WorkflowStep05A(index: 2, title: "Status", kind: .toolCall, toolName: "git.status"),
            WorkflowStep05A(index: 3, title: "Patch", kind: .toolCall, toolName: "file.patch", risk: .high, approval: .askEveryTime),
        ],
        provenance: WorkflowProvenance(sourceSessionID: "s1"))
}

func setupReplayEngine(draft: WorkflowDraft05A? = nil, executor: MockToolExecutor? = nil) async -> (WorkflowReplayEngine, MockToolExecutor, InMemoryWorkflowRunStore) {
    let d = draft ?? makeDraftForReplay()
    let draftStore = InMemoryWorkflowDraftStore()
    try! await draftStore.saveDraft(d)
    let runStore = InMemoryWorkflowRunStore()
    let exec = executor ?? MockToolExecutor()
    let engine = WorkflowReplayEngine(draftStore: draftStore, runStore: runStore, toolExecutor: exec)
    return (engine, exec, runStore)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Step Execution Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Step Execution Policy")
struct StepExecutionPolicyTests {
    let pol = WorkflowStepExecutionPolicy()
    let rp = WorkflowReplayPolicy.readOnlyManual

    func plan(_ tool: String, kind: WorkflowStepKind = .toolCall) -> WorkflowStepPlan {
        WorkflowStepPlan(sourceStepID: "s", index: 1, title: "t", kind: kind, toolName: tool)
    }

    @Test("Read-only tool allowed")
    func readOnlyAllowed() {
        let d = pol.decide(step: plan("file.list"), descriptor: readOnlyDescriptor("file.list"), policy: rp)
        #expect(d.action == .execute)
    }

    @Test("file.patch skipped")
    func filePatchSkipped() {
        let d = pol.decide(step: plan("file.patch"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .writeTool)
    }

    @Test("git.push skipped")
    func gitPushSkipped() {
        let d = pol.decide(step: plan("git.push"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .writeTool)
    }

    @Test("swift.test skipped")
    func swiftTestSkipped() {
        let d = pol.decide(step: plan("swift.test"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .notReadOnly)
    }

    @Test("swift.build skipped")
    func swiftBuildSkipped() {
        let d = pol.decide(step: plan("swift.build"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
    }

    @Test("EVM broadcast skipped")
    func evmBroadcastSkipped() {
        let d = pol.decide(step: plan("evm.tx_broadcast_signed"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .signingOrBroadcast)
    }

    @Test("Solana send skipped")
    func solanaSendSkipped() {
        let d = pol.decide(step: plan("solana.tx_send_signed"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .signingOrBroadcast)
    }

    @Test("EVM balance allowed")
    func evmBalanceAllowed() {
        let d = pol.decide(step: plan("evm.account_balance_native"), descriptor: readOnlyDescriptor("evm.account_balance_native"), policy: rp)
        #expect(d.action == .execute)
    }

    @Test("Solana balance allowed")
    func solanaBalanceAllowed() {
        let d = pol.decide(step: plan("solana.account_balance"), descriptor: readOnlyDescriptor("solana.account_balance"), policy: rp)
        #expect(d.action == .execute)
    }

    @Test("Unknown tool skipped")
    func unknownToolSkipped() {
        let d = pol.decide(step: plan("custom.unknown"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
    }

    @Test("git.commit skipped")
    func gitCommitSkipped() {
        let d = pol.decide(step: plan("git.commit"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
    }

    @Test("file.delete skipped")
    func fileDeleteSkipped() {
        let d = pol.decide(step: plan("file.delete"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .destructiveTool)
    }

    @Test("EVM tx build skipped")
    func evmTxBuildSkipped() {
        let d = pol.decide(step: plan("evm.tx_build_native_transfer"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
        #expect(d.reason == .blockchainWrite)
    }

    @Test("Solana tx build skipped")
    func solanaTxBuildSkipped() {
        let d = pol.decide(step: plan("solana.tx_build_sol_transfer"), descriptor: nil, policy: rp)
        #expect(d.action == .skip)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Replay Engine Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Replay Engine")
struct ReplayEngineTests {

    @Test("Creates workflow run")
    func createsRun() async throws {
        let (engine, _, runStore) = await setupReplayEngine()
        _ = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        let runs = try await runStore.listRuns(draftID: "rd")
        #expect(runs.count == 1)
    }

    @Test("Executes allowed read-only steps")
    func executesReadOnly() async throws {
        let (engine, exec, _) = await setupReplayEngine()
        _ = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        #expect(exec.executedTools.contains("file.list"))
        #expect(exec.executedTools.contains("git.status"))
    }

    @Test("Skips unsafe steps")
    func skipsUnsafe() async throws {
        let (engine, exec, _) = await setupReplayEngine()
        let report = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        #expect(!exec.executedTools.contains("file.patch"))
        #expect(!report.skippedSteps.isEmpty)
    }

    @Test("Step runs persisted")
    func stepRunsPersisted() async throws {
        let (engine, _, runStore) = await setupReplayEngine()
        let report = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        let steps = try await runStore.getStepRuns(runID: report.runID)
        #expect(steps.count == 3)
    }

    @Test("Report has correct status with skips")
    func correctStatusWithSkips() async throws {
        let (engine, _, _) = await setupReplayEngine()
        let report = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        #expect(report.status == .completedWithSkippedSteps)
    }

    @Test("Draft not found throws")
    func draftNotFound() async {
        let store = InMemoryWorkflowDraftStore()
        let runStore = InMemoryWorkflowRunStore()
        let engine = WorkflowReplayEngine(draftStore: store, runStore: runStore, toolExecutor: MockToolExecutor())
        do {
            _ = try await engine.replay(WorkflowReplayRequest(draftID: "nonexistent"))
            Issue.record("Should throw")
        } catch is WorkflowReplayError { } catch { Issue.record("Wrong error") }
    }

    @Test("Summary includes safety statement")
    func summaryHasSafety() async throws {
        let (engine, _, _) = await setupReplayEngine()
        let report = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        #expect(report.summaryMarkdown.contains("read-only"))
    }

    @Test("Tool failure records failed step")
    func toolFailureRecorded() async throws {
        let exec = MockToolExecutor()
        exec.results["file.list"] = ToolExecutionResult(requestID: "r", toolName: "file.list", status: .failed, errorMessage: "boom")
        let draft = makeDraftForReplay(steps: [
            WorkflowStep05A(index: 1, title: "List", kind: .toolCall, toolName: "file.list"),
        ])
        let (engine, _, _) = await setupReplayEngine(draft: draft, executor: exec)
        let report = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        #expect(!report.failedSteps.isEmpty)
    }

    @Test("Does not execute blockchain write tools")
    func noBlockchainWrites() async throws {
        let draft = makeDraftForReplay(steps: [
            WorkflowStep05A(index: 1, title: "Build", kind: .toolCall, toolName: "evm.tx_build_native_transfer"),
            WorkflowStep05A(index: 2, title: "Sign", kind: .toolCall, toolName: "evm.tx_request_signature"),
            WorkflowStep05A(index: 3, title: "Send", kind: .toolCall, toolName: "solana.tx_send_signed"),
        ])
        let (engine, exec, _) = await setupReplayEngine(draft: draft)
        _ = try await engine.replay(WorkflowReplayRequest(draftID: "rd"))
        #expect(exec.executedTools.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Run Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Run Store")
struct RunStoreTests {

    @Test("Save and get run")
    func saveAndGet() async throws {
        let store = InMemoryWorkflowRunStore()
        let run = WorkflowRun05C(id: "r1", draftID: "d1", draftName: "T")
        try await store.saveRun(run)
        let got = try await store.getRun(id: "r1")
        #expect(got?.draftName == "T")
    }

    @Test("List runs by draft")
    func listByDraft() async throws {
        let store = InMemoryWorkflowRunStore()
        try await store.saveRun(WorkflowRun05C(id: "r1", draftID: "d1", draftName: "A"))
        try await store.saveRun(WorkflowRun05C(id: "r2", draftID: "d2", draftName: "B"))
        let d1 = try await store.listRuns(draftID: "d1")
        #expect(d1.count == 1)
    }

    @Test("Save and get step runs")
    func stepRuns() async throws {
        let store = InMemoryWorkflowRunStore()
        try await store.saveStepRun(WorkflowStepRun(runID: "r1", sourceStepID: "s1", index: 1, title: "A"))
        try await store.saveStepRun(WorkflowStepRun(runID: "r1", sourceStepID: "s2", index: 2, title: "B"))
        let steps = try await store.getStepRuns(runID: "r1")
        #expect(steps.count == 2)
        #expect(steps[0].index < steps[1].index)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Output Redaction Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Output Redaction")
struct OutputRedactionTests {
    let redactor = WorkflowOutputRedactor()

    @Test("Redacts API keys")
    func redactsApiKeys() {
        let out = redactor.redactAndTruncate("Found API_KEY=sk-1234", maxBytes: 10000)
        #expect(!out.contains("API_KEY"))
        #expect(out.contains("[REDACTED]"))
    }

    @Test("Redacts passwords")
    func redactsPasswords() {
        let out = redactor.redactAndTruncate("PASSWORD=hunter2", maxBytes: 10000)
        #expect(out.contains("[REDACTED]"))
    }

    @Test("Redacts private keys")
    func redactsPrivateKeys() {
        let out = redactor.redactAndTruncate("PRIVATE_KEY=0xabc", maxBytes: 10000)
        #expect(out.contains("[REDACTED]"))
    }

    @Test("Truncates long output")
    func truncatesLong() {
        let long = String(repeating: "x", count: 20000)
        let out = redactor.redactAndTruncate(long, maxBytes: 1000)
        #expect(out.count < 2000)
        #expect(out.contains("truncated"))
    }

    @Test("Short output passes through")
    func shortPassesThrough() {
        let out = redactor.redactAndTruncate("hello", maxBytes: 10000)
        #expect(out == "hello")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Run Renderer Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Run Renderer")
struct RunRendererTests {
    let renderer = WorkflowRunRenderer()

    @Test("Renders executed and skipped sections")
    func rendersSections() {
        let run = WorkflowRun05C(id: "r1", draftID: "d1", draftName: "Test", status: .completedWithSkippedSteps)
        let steps = [
            WorkflowStepRun(runID: "r1", sourceStepID: "s1", index: 1, title: "Read", toolName: "file.list", status: .succeeded, outputPreview: "3 files"),
            WorkflowStepRun(runID: "r1", sourceStepID: "s2", index: 2, title: "Patch", toolName: "file.patch", status: .skipped, skipReason: .writeTool),
        ]
        let md = renderer.renderReport(run: run, steps: steps)
        #expect(md.contains("Executed"))
        #expect(md.contains("Skipped"))
        #expect(md.contains("read-only steps only"))
        #expect(md.contains("No files were modified"))
    }
}
