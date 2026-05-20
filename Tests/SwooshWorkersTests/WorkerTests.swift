// Tests/SwooshWorkersTests/WorkerTests.swift — 0.7B Tests

import Testing
import Foundation
@testable import SwooshWorkers
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// Fixtures
// ═══════════════════════════════════════════════════════════════

func makeStore() -> InMemoryWorkerStore { InMemoryWorkerStore() }
func makeScheduler(_ store: InMemoryWorkerStore) -> WorkerScheduler { WorkerScheduler(store: store) }

func seedLane(_ store: InMemoryWorkerStore, lane: WorkerLane = WorkerLaneDefaults.devInspector) async {
    await store.saveLane(lane)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Default Lanes Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Default Lanes")
struct DefaultLanesTests {

    @Test("All default lanes exist")
    func allDefaultLanes() {
        let lanes = WorkerLaneDefaults.all()
        #expect(lanes.count == 8)
    }

    @Test("Human lane has zero budget")
    func humanLaneBudget() {
        let lane = WorkerLaneDefaults.human
        #expect(lane.budget.maxTurns == 0)
        #expect(lane.budget.maxToolCalls == 0)
    }

    @Test("Dev inspector is read-only")
    func devInspectorReadOnly() {
        let policy = WorkerToolPolicy.devInspector
        #expect(policy.deniedTools.contains("file.patch"))
        #expect(policy.deniedTools.contains("git.commit"))
        #expect(policy.allowedTools.contains("file.read"))
    }

    @Test("Dev fixer can patch with approval")
    func devFixerCanPatch() {
        let policy = WorkerToolPolicy.devFixer
        #expect(policy.allowedTools.contains("file.patch"))
        #expect(policy.maxRiskWithoutApproval == .low)
    }

    @Test("Blockchain reader cannot build transaction")
    func blockchainReaderNoTxBuild() {
        let policy = WorkerToolPolicy.blockchainReader
        #expect(policy.deniedTools.contains("evm.tx_build_native_transfer"))
        #expect(policy.allowedTools.contains("evm.account_balance_native"))
    }

    @Test("Blockchain reviewer cannot sign")
    func blockchainReviewerNoSign() {
        let policy = WorkerToolPolicy.blockchainReviewer
        #expect(policy.deniedTools.contains("evm.tx_request_signature"))
        #expect(policy.deniedTools.contains("solana.tx_send_signed"))
    }

    @Test("Blockchain reviewer can build transactions")
    func blockchainReviewerCanBuild() {
        let policy = WorkerToolPolicy.blockchainReviewer
        #expect(policy.allowedTools.contains("evm.tx_build_native_transfer"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tool Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Tool Policy")
struct ToolPolicyTests {

    @Test("Global deny blocks git.push")
    func globalDenyGitPush() {
        let policy = WorkerToolPolicy.devFixer
        #expect(!policy.isAllowed("git.push"))
    }

    @Test("Global deny blocks file.delete")
    func globalDenyFileDelete() {
        #expect(!WorkerToolPolicy.readOnly.isAllowed("file.delete"))
    }

    @Test("Global deny blocks signing")
    func globalDenySigning() {
        #expect(!WorkerToolPolicy.devInspector.isAllowed("evm.tx_request_signature"))
        #expect(!WorkerToolPolicy.devInspector.isAllowed("solana.tx_send_signed"))
    }

    @Test("Global deny blocks broadcasting")
    func globalDenyBroadcast() {
        #expect(!WorkerToolPolicy.blockchainReviewer.isAllowed("evm.tx_broadcast_signed"))
    }

    @Test("Global deny blocks approval.resolve")
    func globalDenyApprovalResolve() {
        #expect(!WorkerToolPolicy.readOnly.isAllowed("approval.resolve"))
        #expect(!WorkerToolPolicy.devFixer.isAllowed("approval.resolve"))
    }

    @Test("Worker cannot approve own gate")
    func workerCannotApproveGate() {
        let policy = WorkerToolPolicy.devInspector
        #expect(policy.deniedTools.contains("workflow.approve_gate"))
        #expect(!policy.allowToolApprovalResolution)
    }

    @Test("Worker cannot spawn by default")
    func workerCannotSpawn() {
        #expect(!WorkerToolPolicy.readOnly.allowWorkerSpawning)
        #expect(!WorkerToolPolicy.devInspector.allowWorkerSpawning)
        #expect(!WorkerToolPolicy.devFixer.allowWorkerSpawning)
    }

    @Test("Worker cannot request broader permissions")
    func workerCannotRequestPermissions() {
        #expect(!WorkerToolPolicy.readOnly.allowPermissionRequests)
        #expect(!WorkerToolPolicy.devFixer.allowPermissionRequests)
    }

    @Test("Allowed tool passes")
    func allowedToolPasses() {
        #expect(WorkerToolPolicy.devInspector.isAllowed("file.read"))
        #expect(WorkerToolPolicy.devInspector.isAllowed("git.status"))
    }

    @Test("Denied tool fails")
    func deniedToolFails() {
        #expect(!WorkerToolPolicy.devInspector.isAllowed("file.patch"))
        #expect(!WorkerToolPolicy.devInspector.isAllowed("swift.build"))
    }

    @Test("Tool not in allowed list fails")
    func notInAllowedFails() {
        #expect(!WorkerToolPolicy.devInspector.isAllowed("some.random.tool"))
    }

    @Test("Private key tool blocked")
    func privateKeyBlocked() {
        #expect(!WorkerToolPolicy.blockchainReader.isAllowed("evm.wallet_connect"))
        #expect(!WorkerToolPolicy.blockchainReviewer.isAllowed("solana.wallet_connect"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Worker Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Worker Store")
struct WorkerStoreTests {

    @Test("Save and list lanes")
    func saveAndListLanes() async throws {
        let store = makeStore()
        await store.saveLane(WorkerLaneDefaults.devInspector)
        let lanes = await store.listLanes()
        #expect(lanes.count == 1)
    }

    @Test("Save and get assignment")
    func saveAndGetAssignment() async throws {
        let store = makeStore()
        let a = WorkerAssignment(cardID: "c1", laneID: "swoosh.dev-inspector")
        await store.saveAssignment(a)
        let got = await store.getAssignment(id: a.id)
        #expect(got?.cardID == "c1")
    }

    @Test("Save and get run")
    func saveAndGetRun() async throws {
        let store = makeStore()
        let run = WorkerRun(assignmentID: "a1", cardID: "c1", laneID: "l1", sessionID: "s1")
        await store.saveRun(run)
        #expect(await store.getRun(id: run.id) != nil)
    }

    @Test("Save heartbeats and logs")
    func heartbeatsAndLogs() async throws {
        let store = makeStore()
        await store.saveHeartbeat(WorkerHeartbeat(runID: "r1", cardID: "c1", status: .running))
        await store.saveLog(WorkerLog(runID: "r1", level: .info, message: "Started"))
        #expect(await store.listHeartbeats(runID: "r1").count == 1)
        #expect(await store.listLogs(runID: "r1").count == 1)
    }

    @Test("Save artifact and result")
    func artifactAndResult() async throws {
        let store = makeStore()
        await store.saveArtifact(WorkerArtifact(runID: "r1", cardID: "c1", kind: .report, title: "Report", uri: "/tmp/r"))
        let result = WorkerResult(runID: "r1", cardID: "c1", status: .completed, summary: "Done")
        await store.saveResult(result)
        #expect(await store.listArtifacts(runID: "r1").count == 1)
        #expect(await store.getResult(id: result.id) != nil)
    }

    @Test("Save escalation")
    func escalation() async throws {
        let store = makeStore()
        await store.saveEscalation(WorkerEscalation(runID: "r1", cardID: "c1", reason: .permissionDenied, message: "No access"))
        #expect(await store.listEscalations(runID: "r1").count == 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Worker Scheduler Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Worker Scheduler")
struct WorkerSchedulerTests {

    @Test("Assign card to lane")
    func assignCard() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        #expect(a.status == .assigned)
    }

    @Test("Disabled lane rejects assignment")
    func disabledLaneRejects() async throws {
        let store = makeStore()
        var lane = WorkerLaneDefaults.devInspector
        lane.enabled = false
        await store.saveLane(lane)
        let sched = makeScheduler(store)
        do {
            _ = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
            Issue.record("Should throw")
        } catch is WorkerError {}
    }

    @Test("Lane not found throws")
    func laneNotFound() async throws {
        let store = makeStore()
        let sched = makeScheduler(store)
        do {
            _ = try await sched.assign(cardID: "c1", laneID: "nonexistent")
            Issue.record("Should throw")
        } catch is WorkerError {}
    }

    @Test("Start run creates worker run")
    func startRun() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        #expect(run.status == .pending)
        #expect(run.laneID == "swoosh.dev-inspector")
    }

    @Test("Lane at capacity rejects")
    func laneAtCapacity() async throws {
        let store = makeStore()
        var lane = WorkerLaneDefaults.devInspector
        lane.maxConcurrentRuns = 1
        await store.saveLane(lane)
        let sched = makeScheduler(store)
        let a1 = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        var run = try await sched.startRun(assignmentID: a1.id)
        // Manually set to running
        run.status = .running
        await store.updateRun(run)
        let a2 = try await sched.assign(cardID: "c2", laneID: "swoosh.dev-inspector")
        do {
            _ = try await sched.startRun(assignmentID: a2.id)
            Issue.record("Should throw capacity")
        } catch is WorkerError {}
    }

    @Test("Record heartbeat")
    func recordHeartbeat() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        try await sched.recordHeartbeat(runID: run.id, message: "Working")
        let hbs = try await sched.listHeartbeats(runID: run.id)
        #expect(hbs.count == 1)
    }

    @Test("Record log")
    func recordLog() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        try await sched.recordLog(runID: run.id, level: .info, message: "Inspecting files")
        let logs = try await sched.listLogs(runID: run.id)
        #expect(logs.count == 1)
    }

    @Test("Complete run")
    func completeRun() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        let result = try await sched.complete(runID: run.id, summary: "Found 3 issues.")
        #expect(result.status == .completed)
        let updated = try await sched.getAssignment(a.id)
        #expect(updated?.status == .completed)
    }

    @Test("Escalate run")
    func escalateRun() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        let esc = try await sched.escalate(runID: run.id, reason: .permissionDenied, message: "Need file.patch")
        #expect(esc.reason == .permissionDenied)
        let updated = try await sched.getAssignment(a.id)
        #expect(updated?.status == .blocked)
    }

    @Test("Cancel run")
    func cancelRun() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        try await sched.cancel(runID: run.id)
        let got = try await sched.getRun(run.id)
        #expect(got?.status == .cancelled)
    }

    @Test("/why explains worker run")
    func whyExplains() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        let why = try await sched.whyExplanation(runID: run.id)
        #expect(why.contains("Worker cannot approve gates"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Budget Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Worker Budget")
struct WorkerBudgetTests {

    @Test("Budget exceeded on tool calls")
    func budgetExceededToolCalls() {
        var run = WorkerRun(assignmentID: "a1", cardID: "c1", laneID: "l1", sessionID: "s1",
            budget: WorkerBudget(maxTurns: 100, maxToolCalls: 2, maxWallClockSeconds: 999, maxTokensApprox: nil))
        run.toolCallCount = 2
        #expect(run.isBudgetExceeded)
    }

    @Test("Budget exceeded on turns")
    func budgetExceededTurns() {
        var run = WorkerRun(assignmentID: "a1", cardID: "c1", laneID: "l1", sessionID: "s1",
            budget: WorkerBudget(maxTurns: 3, maxToolCalls: 100, maxWallClockSeconds: 999, maxTokensApprox: nil))
        run.turnCount = 3
        #expect(run.isBudgetExceeded)
    }

    @Test("Budget not exceeded initially")
    func budgetNotExceeded() {
        let run = WorkerRun(assignmentID: "a1", cardID: "c1", laneID: "l1", sessionID: "s1")
        #expect(!run.isBudgetExceeded)
    }

    @Test("Tool call tracking increments budget")
    func toolCallTracking() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        try await sched.recordToolCall(runID: run.id)
        let got = try await sched.getRun(run.id)
        #expect(got?.toolCallCount == 1)
    }

    @Test("Small budget values")
    func smallBudgetValues() {
        let b = WorkerBudget.small
        #expect(b.maxTurns == 8)
        #expect(b.maxToolCalls == 16)
        #expect(b.maxWallClockSeconds == 300)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Subagent Isolation Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Subagent Isolation")
struct SubagentIsolationTests {

    @Test("Worker isolation defaults")
    func workerDefaults() {
        let policy = SubagentIsolationPolicy.forWorker()
        #expect(policy.separateSession)
        #expect(policy.separateTranscript)
        #expect(policy.finalSummaryOnlyToParent)
        #expect(!policy.allowMemoryWrites)
        #expect(policy.allowBoardWrites)
    }

    @Test("Worker cannot write memory")
    func cannotWriteMemory() {
        let policy = SubagentIsolationPolicy.forWorker()
        #expect(!policy.allowMemoryWrites)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Content Redaction Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Worker Redaction")
struct WorkerRedactionTests {

    @Test("Redacts private keys")
    func redactsPrivateKey() {
        let r = WorkerContentRedactor()
        #expect(!r.redact("-----BEGIN PRIVATE KEY").contains("-----BEGIN"))
    }

    @Test("Redacts seed phrases")
    func redactsSeed() {
        let r = WorkerContentRedactor()
        #expect(!r.redact("seed: word1 word2").contains("seed:"))
    }

    @Test("Redacts cookies")
    func redactsCookies() {
        let r = WorkerContentRedactor()
        #expect(!r.redact("cookie: session=abc").contains("cookie:"))
    }

    @Test("Redacts session tokens")
    func redactsSessionToken() {
        let r = WorkerContentRedactor()
        #expect(!r.redact("session_token=xyz").contains("session_token"))
    }

    @Test("Redacts bearer tokens")
    func redactsBearer() {
        let r = WorkerContentRedactor()
        #expect(!r.redact("Bearer eyJhbGciOi").contains("Bearer "))
    }

    @Test("Log messages are redacted by scheduler")
    func logRedactedByScheduler() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        try await sched.recordLog(runID: run.id, level: .info, message: "Found cookie: session=abc")
        let logs = try await sched.listLogs(runID: run.id)
        #expect(!logs[0].message.contains("cookie:"))
    }

    @Test("Heartbeat messages are redacted")
    func heartbeatRedacted() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        try await sched.recordHeartbeat(runID: run.id, message: "Processing -----BEGIN data")
        let hbs = try await sched.listHeartbeats(runID: run.id)
        #expect(!hbs[0].message!.contains("-----BEGIN"))
    }

    @Test("Result summary is redacted")
    func resultRedacted() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        let result = try await sched.complete(runID: run.id, summary: "Found mnemonic: word1 word2 word3")
        #expect(!result.summary.contains("mnemonic:"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Escalation Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Worker Escalation")
struct WorkerEscalationTests {

    @Test("Escalation reasons")
    func reasons() {
        #expect(WorkerEscalationReason.approvalNeeded.rawValue == "approvalNeeded")
        #expect(WorkerEscalationReason.budgetExceeded.rawValue == "budgetExceeded")
    }

    @Test("Escalation message redacted")
    func escalationRedacted() async throws {
        let store = makeStore()
        await seedLane(store)
        let sched = makeScheduler(store)
        let a = try await sched.assign(cardID: "c1", laneID: "swoosh.dev-inspector")
        let run = try await sched.startRun(assignmentID: a.id)
        let esc = try await sched.escalate(runID: run.id, reason: .failedTool, message: "Error with sk_live_key123")
        #expect(!esc.message.contains("sk_"))
    }
}
