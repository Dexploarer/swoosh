// Tests/SwooshFlowTests/WorkflowExecutionTests.swift — 0.5D Tests

import Testing
import Foundation
@testable import SwooshFlow
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Fixtures
// ═══════════════════════════════════════════════════════════════

func makeDraftForExec() -> WorkflowDraft05A {
    WorkflowDraft05A(id: "ed", name: "Fix Loop", summary: "t", steps: [
        WorkflowStep05A(index: 0, title: "List", kind: .toolCall, toolName: "file.list"),
        WorkflowStep05A(index: 1, title: "Status", kind: .toolCall, toolName: "git.status"),
        WorkflowStep05A(index: 2, title: "Test", kind: .toolCall, toolName: "swift.test", risk: .medium, approval: .askFirstTime),
        WorkflowStep05A(index: 3, title: "Patch", kind: .toolCall, toolName: "file.patch", risk: .high, approval: .askEveryTime),
        WorkflowStep05A(index: 4, title: "Commit", kind: .toolCall, toolName: "git.commit", risk: .high, approval: .askEveryTime),
        WorkflowStep05A(index: 5, title: "Push", kind: .toolCall, toolName: "git.push", risk: .critical),
    ], provenance: WorkflowProvenance(sourceSessionID: "s"))
}

func setupExecEngine(draft: WorkflowDraft05A? = nil) async -> (WorkflowExecutionEngine, MockToolExecutor, InMemoryWorkflowRunStore, InMemoryGateStore) {
    let d = draft ?? makeDraftForExec()
    let ds = InMemoryWorkflowDraftStore(); try! await ds.saveDraft(d)
    let rs = InMemoryWorkflowRunStore(); let gs = InMemoryGateStore()
    let exec = MockToolExecutor()
    let engine = WorkflowExecutionEngine(draftStore: ds, runStore: rs, gateStore: gs, toolExecutor: exec)
    return (engine, exec, rs, gs)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Decision Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Execution Decision Policy")
struct ExecutionDecisionPolicyTests {
    let dp = WorkflowExecutionDecisionPolicy()
    let pol = WorkflowExecutionPolicy.manualApprovalGated

    @Test("Read-only executes now")
    func readOnlyExecutes() {
        let d = dp.decide(toolName: "file.list", risk: .readOnly, policy: pol)
        #expect(d.action == .executeNow)
    }

    @Test("swift.test pauses for approval")
    func swiftTestPauses() {
        let d = dp.decide(toolName: "swift.test", risk: .medium, policy: pol)
        #expect(d.action == .pauseForApproval)
    }

    @Test("file.patch pauses for approval")
    func filePatchPauses() {
        let d = dp.decide(toolName: "file.patch", risk: .high, policy: pol)
        #expect(d.action == .pauseForApproval)
    }

    @Test("git.commit pauses for approval")
    func gitCommitPauses() {
        let d = dp.decide(toolName: "git.commit", risk: .high, policy: pol)
        #expect(d.action == .pauseForApproval)
    }

    @Test("git.push blocked")
    func gitPushBlocked() {
        let d = dp.decide(toolName: "git.push", risk: .critical, policy: pol)
        #expect(d.action == .block)
    }

    @Test("file.delete blocked")
    func fileDeleteBlocked() {
        let d = dp.decide(toolName: "file.delete", risk: .critical, policy: pol)
        #expect(d.action == .block)
    }

    @Test("EVM tx build pauses")
    func evmTxBuildPauses() {
        let d = dp.decide(toolName: "evm.tx_build_native_transfer", risk: .high, policy: pol)
        #expect(d.action == .pauseForApproval)
    }

    @Test("EVM broadcast blocked")
    func evmBroadcastBlocked() {
        let d = dp.decide(toolName: "evm.tx_broadcast_signed", risk: .critical, policy: pol)
        #expect(d.action == .block)
    }

    @Test("Solana tx build pauses")
    func solanaTxBuildPauses() {
        let d = dp.decide(toolName: "solana.tx_build_sol_transfer", risk: .high, policy: pol)
        #expect(d.action == .pauseForApproval)
    }

    @Test("Solana send blocked")
    func solanaSendBlocked() {
        let d = dp.decide(toolName: "solana.tx_send_signed", risk: .critical, policy: pol)
        #expect(d.action == .block)
    }

    @Test("EVM signing blocked")
    func evmSigningBlocked() {
        let d = dp.decide(toolName: "evm.tx_request_signature", risk: .critical, policy: pol)
        #expect(d.action == .block)
    }

    @Test("swift.build pauses")
    func swiftBuildPauses() {
        let d = dp.decide(toolName: "swift.build", risk: .medium, policy: pol)
        #expect(d.action == .pauseForApproval)
    }

    @Test("EVM balance executes")
    func evmBalanceExecutes() {
        let d = dp.decide(toolName: "evm.account_balance_native", risk: .readOnly, policy: pol)
        #expect(d.action == .executeNow)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Gate Lifecycle Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Gate Lifecycle")
struct GateLifecycleTests {

    @Test("Gate created and saved")
    func gateCreated() async throws {
        let store = InMemoryGateStore()
        let gate = WorkflowExecutionGate(id: "g1", runID: "r", stepID: "s", stepIndex: 0,
            stepTitle: "Test", toolName: "swift.test", risk: .medium,
            preview: WorkflowStepApprovalPreview(toolName: "swift.test", humanSummary: "Run tests"))
        try await store.saveGate(gate)
        let got = try await store.getGate(id: "g1")
        #expect(got?.status == .pending)
    }

    @Test("Approve changes status")
    func approveChanges() async throws {
        let store = InMemoryGateStore()
        let gate = WorkflowExecutionGate(id: "g1", runID: "r", stepID: "s", stepIndex: 0,
            stepTitle: "T", toolName: "t", risk: .medium,
            preview: WorkflowStepApprovalPreview(toolName: "t", humanSummary: ""))
        try await store.saveGate(gate)
        try await store.resolveGate(id: "g1", status: .approved, by: .human, reason: nil)
        let got = try await store.getGate(id: "g1")
        #expect(got?.status == .approved)
        #expect(got?.resolvedBy == .human)
    }

    @Test("Deny changes status")
    func denyChanges() async throws {
        let store = InMemoryGateStore()
        let gate = WorkflowExecutionGate(id: "g1", runID: "r", stepID: "s", stepIndex: 0,
            stepTitle: "T", toolName: "t", risk: .medium,
            preview: WorkflowStepApprovalPreview(toolName: "t", humanSummary: ""))
        try await store.saveGate(gate)
        try await store.resolveGate(id: "g1", status: .denied, by: .human, reason: "no")
        let got = try await store.getGate(id: "g1")
        #expect(got?.status == .denied)
        #expect(got?.denialReason == "no")
    }

    @Test("Model cannot approve gate")
    func modelCannotApprove() async {
        let (engine, _, _, _) = await setupExecEngine()
        do {
            try await engine.approveGate(gateID: "g1", origin: .model, confirmation: nil)
            Issue.record("Should throw")
        } catch WorkflowExecutionError.cannotApproveAsModel { }
        catch { Issue.record("Wrong error") }
    }

    @Test("High-risk requires confirmation")
    func highRiskRequiresConfirm() async throws {
        let (engine, _, _, gs) = await setupExecEngine()
        let gate = WorkflowExecutionGate(id: "g1", runID: "r", stepID: "s", stepIndex: 0,
            stepTitle: "T", toolName: "file.patch", risk: .high,
            preview: WorkflowStepApprovalPreview(toolName: "file.patch", humanSummary: ""))
        try await gs.saveGate(gate)
        do {
            try await engine.approveGate(gateID: "g1", origin: .human, confirmation: nil)
            Issue.record("Should throw")
        } catch WorkflowExecutionError.highRiskRequiresConfirmation { }
        catch { Issue.record("Wrong error") }
    }

    @Test("High-risk approves with confirmation")
    func highRiskApprovesWithConfirm() async throws {
        let (engine, _, _, gs) = await setupExecEngine()
        let gate = WorkflowExecutionGate(id: "g1", runID: "r", stepID: "s", stepIndex: 0,
            stepTitle: "T", toolName: "file.patch", risk: .high,
            preview: WorkflowStepApprovalPreview(toolName: "file.patch", humanSummary: ""))
        try await gs.saveGate(gate)
        try await engine.approveGate(gateID: "g1", origin: .human, confirmation: "Apply patch")
        let got = try await gs.getGate(id: "g1")
        #expect(got?.status == .approved)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Execution Engine Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Execution Engine")
struct ExecutionEngineTests {

    @Test("Start creates run")
    func startCreatesRun() async throws {
        let (engine, _, rs, _) = await setupExecEngine()
        _ = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        let runs = try await rs.listRuns(draftID: "ed")
        #expect(!runs.isEmpty)
    }

    @Test("Executes read-only steps automatically")
    func executesReadOnly() async throws {
        let (engine, exec, _, _) = await setupExecEngine()
        _ = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        #expect(exec.executedTools.contains("file.list"))
        #expect(exec.executedTools.contains("git.status"))
    }

    @Test("Pauses at first approval gate")
    func pausesAtGate() async throws {
        let (engine, exec, _, gs) = await setupExecEngine()
        let report = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        #expect(report.status == .pausedForApproval)
        #expect(report.pendingGateID != nil)
        // swift.test should not have executed
        #expect(!exec.executedTools.contains("swift.test"))
    }

    @Test("git.push blocked in report")
    func gitPushBlocked() async throws {
        // Use a draft with only push
        let draft = WorkflowDraft05A(id: "ed", name: "Push", summary: "t", steps: [
            WorkflowStep05A(index: 0, title: "Push", kind: .toolCall, toolName: "git.push", risk: .critical),
        ], provenance: WorkflowProvenance(sourceSessionID: "s"))
        let (engine, exec, _, _) = await setupExecEngine(draft: draft)
        let report = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        #expect(exec.executedTools.isEmpty)
        #expect(!report.skippedSteps.isEmpty || report.status == .completedWithSkippedSteps || report.status == .completed)
    }

    @Test("Cancel stops run")
    func cancelStops() async throws {
        let (engine, _, rs, _) = await setupExecEngine()
        let report = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        let cancelReport = try await engine.cancel(runID: report.runID)
        #expect(cancelReport.status == .cancelled)
    }

    @Test("Report summary mentions no signing")
    func reportMentionsNoSigning() async throws {
        let (engine, _, _, _) = await setupExecEngine()
        let report = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        #expect(report.summaryMarkdown.contains("signing"))
    }

    @Test("Blockchain signing tools do not execute")
    func blockchainSigningBlocked() async throws {
        let draft = WorkflowDraft05A(id: "ed", name: "BC", summary: "t", steps: [
            WorkflowStep05A(index: 0, title: "Sign", kind: .toolCall, toolName: "evm.tx_request_signature"),
            WorkflowStep05A(index: 1, title: "Send", kind: .toolCall, toolName: "solana.tx_send_signed"),
        ], provenance: WorkflowProvenance(sourceSessionID: "s"))
        let (engine, exec, _, _) = await setupExecEngine(draft: draft)
        _ = try await engine.start(WorkflowExecutionRequest(draftID: "ed"))
        #expect(exec.executedTools.isEmpty)
    }

    @Test("Draft not found throws")
    func draftNotFound() async {
        let ds = InMemoryWorkflowDraftStore(); let rs = InMemoryWorkflowRunStore(); let gs = InMemoryGateStore()
        let engine = WorkflowExecutionEngine(draftStore: ds, runStore: rs, gateStore: gs, toolExecutor: MockToolExecutor())
        do {
            _ = try await engine.start(WorkflowExecutionRequest(draftID: "nope"))
            Issue.record("Should throw")
        } catch is WorkflowExecutionError { } catch { Issue.record("Wrong") }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Rollback Hint Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Rollback Hints")
struct RollbackHintTests {
    @Test("File patch has backup hint")
    func patchBackup() {
        let h = WorkflowRollbackHint(kind: .backupFile, description: "Backup before patch.")
        #expect(h.kind == .backupFile)
        #expect(h.available)
    }

    @Test("Git commit has reset hint")
    func commitReset() {
        let h = WorkflowRollbackHint(kind: .gitReset, description: "git reset --soft HEAD~1")
        #expect(h.kind == .gitReset)
    }

    @Test("Not applicable hint")
    func notApplicable() {
        let h = WorkflowRollbackHint(kind: .notApplicable, description: "No rollback.", available: false)
        #expect(!h.available)
    }
}
