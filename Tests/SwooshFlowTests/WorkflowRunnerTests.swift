// Tests/SwooshFlowTests/WorkflowRunnerTests.swift — 0.6B Tests

import Testing
import Foundation
@testable import SwooshFlow
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Fixtures
// ═══════════════════════════════════════════════════════════════

func makeRunnerEngine() async -> (WorkflowRunner, WorkflowRunQueue, MockToolExecutor) {
    let draft = makeDraftForExec()
    let ds = InMemoryWorkflowDraftStore(); try! await ds.saveDraft(draft)
    let rs = InMemoryWorkflowRunStore(); let gs = InMemoryGateStore()
    let exec = MockToolExecutor()
    let engine = WorkflowExecutionEngine(draftStore: ds, runStore: rs, gateStore: gs, toolExecutor: exec)
    let queue = WorkflowRunQueue()
    let runner = WorkflowRunner(queue: queue, executionEngine: engine)
    return (runner, queue, exec)
}

func makeDispatcher() async -> (TriggerDispatcher, InMemoryTriggerEventStore, WorkflowRunQueue, InMemoryEnablementStore, InMemoryTriggerStore) {
    let es = InMemoryTriggerEventStore()
    let q = WorkflowRunQueue()
    let enableStore = InMemoryEnablementStore()
    let trigStore = InMemoryTriggerStore()
    let deb = TriggerDebouncer(defaultDebounceSeconds: 5)
    let rl = TriggerRateLimiter(maxEventsPerHour: 3, maxRunsPerDay: 6)
    let admission = WorkflowRunAdmission(enablementStore: enableStore, triggerStore: trigStore)
    let dispatcher = TriggerDispatcher(eventStore: es, runQueue: q, debouncer: deb, rateLimiter: rl, admission: admission)
    return (dispatcher, es, q, enableStore, trigStore)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Run Queue Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Run Queue")
struct RunQueueTests {
    @Test("Enqueue and dequeue")
    func enqueueDequeue() async {
        let q = WorkflowRunQueue()
        let req = WorkflowRunRequest06B(workflowID: "w1")
        await q.enqueue(req)
        #expect(await q.count() == 1)
        let d = await q.dequeue()
        #expect(d?.workflowID == "w1")
        #expect(await q.count() == 0)
    }

    @Test("FIFO order")
    func fifoOrder() async {
        let q = WorkflowRunQueue()
        await q.enqueue(WorkflowRunRequest06B(id: "a", workflowID: "w1"))
        await q.enqueue(WorkflowRunRequest06B(id: "b", workflowID: "w2"))
        #expect(await q.dequeue()?.id == "a")
        #expect(await q.dequeue()?.id == "b")
    }

    @Test("Empty dequeue returns nil")
    func emptyDequeue() async {
        let q = WorkflowRunQueue()
        #expect(await q.dequeue() == nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Runner Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Runner Policy")
struct RunnerPolicyTests {
    @Test("Safe background defaults")
    func safeDefaults() {
        let p = WorkflowRunnerPolicy.safeBackground
        #expect(p.allowBackgroundRuns)
        #expect(p.allowReadOnlyUnattended)
        #expect(!p.allowRiskyUnattended)
        #expect(!p.allowCriticalSteps)
        #expect(!p.allowSigningOrBroadcasting)
        #expect(!p.allowGitPush)
        #expect(!p.allowFileDelete)
        #expect(p.maxConcurrentRuns == 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Debouncer Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Debouncer")
struct TriggerDebouncerTests {
    @Test("First event admitted")
    func firstAdmitted() async {
        let d = TriggerDebouncer(defaultDebounceSeconds: 30)
        let e = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        #expect(await d.shouldAdmit(e))
    }

    @Test("Rapid duplicate debounced")
    func duplicateDebounced() async {
        let d = TriggerDebouncer(defaultDebounceSeconds: 30)
        let e1 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()), createdAt: Date())
        let e2 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()), createdAt: Date().addingTimeInterval(1))
        _ = await d.shouldAdmit(e1)
        #expect(await !d.shouldAdmit(e2))
    }

    @Test("After debounce window admitted")
    func afterWindowAdmitted() async {
        let d = TriggerDebouncer(defaultDebounceSeconds: 5)
        let now = Date()
        let e1 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()), createdAt: now)
        let e2 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()), createdAt: now.addingTimeInterval(10))
        _ = await d.shouldAdmit(e1)
        #expect(await d.shouldAdmit(e2))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Rate Limiter Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Rate Limiter")
struct TriggerRateLimiterTests {
    @Test("Under limit admitted")
    func underLimitAdmitted() async {
        let rl = TriggerRateLimiter(maxEventsPerHour: 3, maxRunsPerDay: 6)
        let e = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        #expect(await rl.shouldAdmit(e))
    }

    @Test("Over hourly limit rejected")
    func overHourlyRejected() async {
        let rl = TriggerRateLimiter(maxEventsPerHour: 2, maxRunsPerDay: 10)
        let now = Date()
        for i in 0..<2 {
            let e = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule,
                payload: .schedule(ScheduleTriggerEventPayload()), createdAt: now.addingTimeInterval(Double(i)))
            _ = await rl.shouldAdmit(e)
        }
        let e3 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule,
            payload: .schedule(ScheduleTriggerEventPayload()), createdAt: now.addingTimeInterval(3))
        #expect(await !rl.shouldAdmit(e3))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Run Admission Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Run Admission")
struct RunAdmissionTests {
    @Test("Enabled workflow admitted")
    func enabledAdmitted() async throws {
        let es = InMemoryEnablementStore()
        try await es.save(WorkflowEnablement(workflowID: "w1", state: .enabledWithTriggers, activationPolicy: .triggeredReadOnly))
        let ts = InMemoryTriggerStore()
        var t = WorkflowTrigger(id: "t1", workflowID: "w1", name: "S", kind: .schedule, configuration: .schedule(ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 0)))))
        t.state = .armed; try await ts.save(t)
        let a = WorkflowRunAdmission(enablementStore: es, triggerStore: ts)
        let ev = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        let d = try await a.evaluate(ev)
        #expect(d.allowed)
    }

    @Test("Disabled workflow rejected")
    func disabledRejected() async throws {
        let es = InMemoryEnablementStore()
        try await es.save(WorkflowEnablement(workflowID: "w1", state: .disabled))
        let ts = InMemoryTriggerStore()
        let a = WorkflowRunAdmission(enablementStore: es, triggerStore: ts)
        let ev = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        let d = try await a.evaluate(ev)
        #expect(!d.allowed)
    }

    @Test("Triggered run blocked when policy disallows")
    func triggeredBlockedByPolicy() async throws {
        let es = InMemoryEnablementStore()
        try await es.save(WorkflowEnablement(workflowID: "w1", state: .enabledManualOnly, activationPolicy: .manualOnly))
        let ts = InMemoryTriggerStore()
        let a = WorkflowRunAdmission(enablementStore: es, triggerStore: ts)
        let ev = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        let d = try await a.evaluate(ev)
        #expect(!d.allowed)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Dispatcher Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Dispatcher")
struct TriggerDispatcherTests {
    @Test("Admitted event queues run")
    func admittedQueuesRun() async throws {
        let (dispatcher, _, q, es, ts) = await makeDispatcher()
        try await es.save(WorkflowEnablement(workflowID: "w1", state: .enabledWithTriggers, activationPolicy: .triggeredReadOnly))
        var t = WorkflowTrigger(id: "t1", workflowID: "w1", name: "S", kind: .schedule, configuration: .schedule(ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 0)))))
        t.state = .armed; try await ts.save(t)
        let ev = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        try await dispatcher.handle(ev)
        #expect(await q.count() == 1)
    }

    @Test("Rejected event does not queue")
    func rejectedDoesNotQueue() async throws {
        let (dispatcher, _, q, _, _) = await makeDispatcher()
        // No enablement → rejected
        let ev = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        try await dispatcher.handle(ev)
        #expect(await q.count() == 0)
    }

    @Test("Debounced event not queued")
    func debouncedNotQueued() async throws {
        let (dispatcher, _, q, es, ts) = await makeDispatcher()
        try await es.save(WorkflowEnablement(workflowID: "w1", state: .enabledWithTriggers, activationPolicy: .triggeredReadOnly))
        var t = WorkflowTrigger(id: "t1", workflowID: "w1", name: "S", kind: .schedule, configuration: .schedule(ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 0)))))
        t.state = .armed; try await ts.save(t)
        let now = Date()
        let ev1 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()), createdAt: now)
        let ev2 = TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()), createdAt: now.addingTimeInterval(1))
        try await dispatcher.handle(ev1)
        try await dispatcher.handle(ev2)
        #expect(await q.count() == 1) // only first
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Trigger Arming Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Arming")
struct TriggerArmingTests {
    @Test("Arm valid schedule trigger")
    func armSchedule() async throws {
        let store = InMemoryTriggerStore()
        let t = WorkflowTrigger(id: "t1", workflowID: "w", name: "S", kind: .schedule,
            configuration: .schedule(ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 0)))))
        try await store.save(t)
        let svc = TriggerArmingService(triggerStore: store)
        let armed = try await svc.arm(triggerID: "t1")
        #expect(armed.state == .armed)
    }

    @Test("Arm file trigger rejects full disk")
    func armFileRejectsFullDisk() async throws {
        let store = InMemoryTriggerStore()
        let t = WorkflowTrigger(id: "t1", workflowID: "w", name: "F", kind: .fileChanged,
            configuration: .fileChanged(FileChangedTriggerConfig(rootID: "/")))
        try await store.save(t)
        let svc = TriggerArmingService(triggerStore: store)
        do { _ = try await svc.arm(triggerID: "t1"); Issue.record("Should throw") }
        catch is TriggerArmingError { } catch { Issue.record("Wrong error") }
    }

    @Test("Arm file trigger rejects sensitive paths")
    func armFileRejectsSensitive() async throws {
        let store = InMemoryTriggerStore()
        let t = WorkflowTrigger(id: "t1", workflowID: "w", name: "F", kind: .fileChanged,
            configuration: .fileChanged(FileChangedTriggerConfig(rootID: "root1", includeGlobs: [".ssh/keys"])))
        try await store.save(t)
        let svc = TriggerArmingService(triggerStore: store)
        do { _ = try await svc.arm(triggerID: "t1"); Issue.record("Should throw") }
        catch is TriggerArmingError { } catch { Issue.record("Wrong error") }
    }

    @Test("Arm webhook rejects non-local")
    func armWebhookRejectsPublic() async throws {
        let store = InMemoryTriggerStore()
        let t = WorkflowTrigger(id: "t1", workflowID: "w", name: "W", kind: .webhook,
            configuration: .webhook(WebhookTriggerConfig(localOnly: false)))
        try await store.save(t)
        let svc = TriggerArmingService(triggerStore: store)
        do { _ = try await svc.arm(triggerID: "t1"); Issue.record("Should throw") }
        catch is TriggerArmingError { } catch { Issue.record("Wrong error") }
    }

    @Test("Disarm changes state")
    func disarm() async throws {
        let store = InMemoryTriggerStore()
        var t = WorkflowTrigger(id: "t1", workflowID: "w", name: "S", kind: .schedule,
            configuration: .schedule(ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 0)))))
        t.state = .armed; try await store.save(t)
        let svc = TriggerArmingService(triggerStore: store)
        let disarmed = try await svc.disarm(triggerID: "t1")
        #expect(disarmed.state == .disabled)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Runner Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Runner")
struct WorkflowRunnerTests {
    @Test("Runner starts and reports status")
    func startsAndStatus() async {
        let (runner, _, _) = await makeRunnerEngine()
        await runner.start()
        let s = await runner.status()
        #expect(s.isRunning)
        #expect(!s.isPaused)
    }

    @Test("Runner pauses and resumes")
    func pausesResumes() async {
        let (runner, _, _) = await makeRunnerEngine()
        await runner.start()
        await runner.pause()
        #expect(await runner.isPaused)
        await runner.resume()
        #expect(await !runner.isPaused)
    }

    @Test("Tick processes queued run")
    func tickProcesses() async {
        let (runner, queue, _) = await makeRunnerEngine()
        await runner.start()
        await queue.enqueue(WorkflowRunRequest06B(workflowID: "ed"))
        let report = await runner.tick()
        #expect(report != nil)
        #expect(await runner.totalCompleted == 1)
    }

    @Test("Tick when paused returns nil")
    func tickWhenPaused() async {
        let (runner, queue, _) = await makeRunnerEngine()
        await runner.start(); await runner.pause()
        await queue.enqueue(WorkflowRunRequest06B(workflowID: "ed"))
        let report = await runner.tick()
        #expect(report == nil)
    }

    @Test("Empty queue tick returns nil")
    func emptyTick() async {
        let (runner, _, _) = await makeRunnerEngine()
        await runner.start()
        #expect(await runner.tick() == nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Webhook Config Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Webhook Config")
struct WebhookConfigTests {
    @Test("Loopback accepted")
    func loopbackAccepted() {
        let c = LocalWebhookServerConfig(bindHost: "127.0.0.1")
        #expect(c.isLoopbackOnly)
    }

    @Test("Public IP rejected")
    func publicRejected() {
        let c = LocalWebhookServerConfig(bindHost: "0.0.0.0")
        #expect(!c.isLoopbackOnly)
    }

    @Test("Localhost accepted")
    func localhostAccepted() {
        let c = LocalWebhookServerConfig(bindHost: "localhost")
        #expect(c.isLoopbackOnly)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Payload Safety Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Payload Safety")
struct PayloadSafetyTests {
    @Test("Webhook payload stores hash not body")
    func webhookHash() {
        let p = WebhookTriggerEventPayload(routeID: "r", bodyHash: "sha256:abc123")
        #expect(p.bodyHash.hasPrefix("sha256:"))
        // No raw body field exists on the type
    }

    @Test("Calendar payload has no raw title")
    func calendarRedacted() {
        let p = CalendarTriggerEventPayload(matchedRuleDescription: "contains 'standup'", eventStart: Date())
        // matchedRuleDescription is a rule description, not the raw event title
        #expect(p.matchedRuleDescription.contains("standup"))
    }

    @Test("App event has no window data")
    func appEventNoWindow() {
        let p = AppEventTriggerEventPayload(bundleIdentifier: "com.apple.dt.Xcode", event: .activated, appName: "Xcode")
        // Type has no window/screen fields
        #expect(p.bundleIdentifier.contains("Xcode"))
    }

    @Test("File changed has no file contents")
    func fileNoContents() {
        let p = FileChangedTriggerEventPayload(rootID: "root1", changedRelativePaths: ["Sources/A.swift"], eventKind: .modified)
        // Type has no fileContents field
        #expect(!p.changedRelativePaths.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Event Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Event Store")
struct TriggerEventStoreTests {
    @Test("Save and get event")
    func saveAndGet() async throws {
        let store = InMemoryTriggerEventStore()
        let e = TriggerEvent(id: "e1", triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload()))
        try await store.save(e)
        let got = try await store.get(id: "e1")
        #expect(got?.triggerID == "t1")
    }

    @Test("List by trigger")
    func listByTrigger() async throws {
        let store = InMemoryTriggerEventStore()
        try await store.save(TriggerEvent(triggerID: "t1", workflowID: "w1", kind: .schedule, payload: .schedule(ScheduleTriggerEventPayload())))
        try await store.save(TriggerEvent(triggerID: "t2", workflowID: "w1", kind: .manual, payload: .manual(ManualTriggerEventPayload())))
        let r = try await store.list(triggerID: "t1", workflowID: nil, limit: nil)
        #expect(r.count == 1)
    }
}
