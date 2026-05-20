// Tests/SwooshApprovalsTests/UnifiedApprovalTests.swift — 0.6C Tests

import Testing
import Foundation
@testable import SwooshApprovals
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// Helper
// ═══════════════════════════════════════════════════════════════

func makePendingApproval(
    id: String = UUID().uuidString, risk: ToolRisk = .medium,
    kind: ApprovalKind06C = .workflowGate,
    confirmation: ConfirmationRequirement = .none,
    expiresAt: Date? = nil
) -> UnifiedApproval {
    UnifiedApproval(
        id: id, kind: kind, title: "Test approval",
        summary: "Test summary", source: ApprovalSource(),
        risk: risk, preview: ApprovalPreview06C(humanSummary: "Summary"),
        confirmationRequirement: confirmation, expiresAt: expiresAt
    )
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Inbox Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Approval Inbox")
struct ApprovalInboxTests {

    @Test("Submit approval")
    func submitApproval() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval()
        try await inbox.submit(a)
        let pending = try await inbox.listPending()
        #expect(pending.count == 1)
    }

    @Test("Resolve approve")
    func resolveApprove() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1")
        try await inbox.submit(a)
        let decision = UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce)
        let resolved = try await inbox.resolve(decision)
        #expect(resolved.status == .approved)
    }

    @Test("Resolve deny")
    func resolveDeny() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1")
        try await inbox.submit(a)
        let decision = UnifiedApprovalDecision(approvalID: "a1", decision: .deny, reason: "Not needed")
        let resolved = try await inbox.resolve(decision)
        #expect(resolved.status == .denied)
    }

    @Test("Expired approval cannot resolve")
    func expiredCannotResolve() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let expired = makePendingApproval(id: "a1", expiresAt: Date().addingTimeInterval(-100))
        try await inbox.submit(expired)
        let decision = UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce)
        do {
            _ = try await inbox.resolve(decision)
            Issue.record("Should throw expired")
        } catch is UnifiedApprovalError {}
    }

    @Test("Already resolved throws")
    func alreadyResolvedThrows() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1")
        try await inbox.submit(a)
        _ = try await inbox.resolve(UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce))
        do {
            _ = try await inbox.resolve(UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce))
            Issue.record("Should throw")
        } catch is UnifiedApprovalError {}
    }

    @Test("History after resolution")
    func historyAfterResolution() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1")
        try await inbox.submit(a)
        _ = try await inbox.resolve(UnifiedApprovalDecision(approvalID: "a1", decision: .deny))
        let history = try await inbox.listHistory()
        #expect(history.count == 1)
        #expect(history[0].status == .denied)
    }

    @Test("Search by title")
    func searchByTitle() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        try await inbox.submit(makePendingApproval())
        let results = try await inbox.search(query: "Test")
        #expect(!results.isEmpty)
    }

    @Test("Group by risk")
    func groupByRisk() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let approvals = [makePendingApproval(risk: .medium), makePendingApproval(risk: .high)]
        let groups = await inbox.groupByRisk(approvals)
        #expect(groups.count == 2)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Confirmation Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Confirmation Requirement")
struct ConfirmationTests {

    @Test("typeContains requires matching text")
    func typeContainsRequired() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1", risk: .high, confirmation: .typeContains("Approve"))
        try await inbox.submit(a)
        // Without confirmation text
        do {
            _ = try await inbox.resolve(UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce))
            Issue.record("Should require confirmation")
        } catch is UnifiedApprovalError {}
    }

    @Test("typeContains with correct text succeeds")
    func typeContainsSucceeds() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1", confirmation: .typeContains("Approve"))
        try await inbox.submit(a)
        let decision = UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce, confirmationText: "I Approve this")
        let resolved = try await inbox.resolve(decision)
        #expect(resolved.status == .approved)
    }

    @Test("typeExact requires exact match")
    func typeExactRequired() async throws {
        let inbox = ApprovalInbox(store: InMemoryUnifiedApprovalStore())
        let a = makePendingApproval(id: "a1", confirmation: .typeExact("BUILD"))
        try await inbox.submit(a)
        let decision = UnifiedApprovalDecision(approvalID: "a1", decision: .approveOnce, confirmationText: "build")
        do {
            _ = try await inbox.resolve(decision)
            Issue.record("Should require exact match")
        } catch is UnifiedApprovalError {}
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Notification Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Notification Policy")
struct NotificationPolicyTests {

    @Test("Low risk suppressed by default")
    func lowRiskSuppressed() {
        let p = NotificationPolicy.safeDefault
        #expect(!p.shouldNotify(risk: .low))
    }

    @Test("Medium risk notified")
    func mediumRiskNotified() {
        #expect(NotificationPolicy.safeDefault.shouldNotify(risk: .medium))
    }

    @Test("High risk notified")
    func highRiskNotified() {
        #expect(NotificationPolicy.safeDefault.shouldNotify(risk: .high))
    }

    @Test("Disabled policy suppresses all")
    func disabledSuppresses() {
        let p = NotificationPolicy(enabled: false, notifyForLowRisk: true, notifyForMediumRisk: true,
            notifyForHighRisk: true, notifyForCriticalRisk: true,
            includeSensitivePreviews: false, maxTitleLength: 80, maxBodyLength: 160)
        #expect(!p.shouldNotify(risk: .high))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Notification Redactor Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Notification Redactor")
struct NotificationRedactorTests {
    let r = NotificationRedactor()

    @Test("Redacts private key marker")
    func redactsPrivateKey() {
        let text = "Found -----BEGIN PRIVATE KEY----- in file"
        let result = r.scrub(text)
        #expect(!result.contains("-----BEGIN"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("Redacts sk_ prefix")
    func redactsSk() {
        let result = r.scrub("API key: sk_live_abc123")
        #expect(!result.contains("sk_"))
    }

    @Test("Redacts seed phrase marker")
    func redactsSeed() {
        let result = r.scrub("Found seed: word1 word2...")
        #expect(!result.contains("seed:"))
    }

    @Test("Redacts cookie marker")
    func redactsCookie() {
        let result = r.scrub("cookie: session=abc")
        #expect(!result.contains("cookie:"))
    }

    @Test("Truncates long text")
    func truncates() {
        let long = String(repeating: "a", count: 200)
        let result = r.redactTitle(long, maxLength: 80)
        #expect(result.count <= 80)
    }

    @Test("Safe text passes through")
    func safePassThrough() {
        let result = r.scrub("Swift Package Health Check paused at swift.test")
        #expect(result == "Swift Package Health Check paused at swift.test")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Notification Router Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Notification Router")
struct NotificationRouterTests {

    @Test("Medium risk approval sends notification")
    func mediumSendsNotification() async throws {
        let router = LocalNotificationRouter()
        let a = makePendingApproval(risk: .medium)
        try await router.notifyApprovalPending(a)
        #expect(await router.sentPayloads.count == 1)
    }

    @Test("High risk sends notification")
    func highSendsNotification() async throws {
        let router = LocalNotificationRouter()
        let a = makePendingApproval(risk: .high)
        try await router.notifyApprovalPending(a)
        let payloads = await router.sentPayloads
        #expect(payloads.count == 1)
        #expect(payloads[0].title.contains("High-risk"))
    }

    @Test("Low risk suppressed by default")
    func lowSuppressed() async throws {
        let router = LocalNotificationRouter()
        let a = makePendingApproval(risk: .low)
        try await router.notifyApprovalPending(a)
        #expect(await router.sentPayloads.isEmpty)
    }

    @Test("Mute suppresses notifications")
    func muteSuppresses() async throws {
        let router = LocalNotificationRouter()
        await router.mute()
        let a = makePendingApproval(risk: .high)
        try await router.notifyApprovalPending(a)
        #expect(await router.sentPayloads.isEmpty)
    }

    @Test("Unmute restores notifications")
    func unmuteRestores() async throws {
        let router = LocalNotificationRouter()
        await router.mute()
        await router.unmute()
        let a = makePendingApproval(risk: .medium)
        try await router.notifyApprovalPending(a)
        #expect(await router.sentPayloads.count == 1)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Factory Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Approval Factory")
struct ApprovalFactoryTests {
    let factory = UnifiedApprovalFactory()

    @Test("From workflow gate")
    func fromGate() {
        let a = factory.forWorkflowGate(
            gateID: "g1", runID: "r1", stepID: "s1", stepTitle: "Run tests",
            toolName: "swift.test", risk: .medium, humanSummary: "Run swift test",
            workflowName: "Health Check"
        )
        #expect(a.kind == .workflowGate)
        #expect(a.title.contains("Run tests"))
    }

    @Test("High risk gate requires confirmation")
    func highRiskConfirmation() {
        let a = factory.forWorkflowGate(
            gateID: "g1", runID: "r1", stepID: "s1", stepTitle: "Patch",
            toolName: "file.patch", risk: .high, humanSummary: "Apply patch",
            workflowName: "Fix"
        )
        if case .typeContains = a.confirmationRequirement {
            // expected
        } else {
            Issue.record("High risk should require typeContains confirmation")
        }
    }

    @Test("From tool approval record")
    func fromToolApproval() {
        let record = ApprovalRecord(sessionID: "s1", toolName: "swift.test", risk: .medium,
            permission: .fileRead, inputPreview: "test", origin: .model)
        let a = factory.fromToolApproval(record)
        #expect(a.kind == .toolCall)
    }

    @Test("For trigger arming")
    func forTriggerArm() {
        let a = factory.forTriggerArming(triggerID: "t1", workflowName: "HC", triggerKind: "schedule")
        #expect(a.kind == .triggerArming)
        #expect(a.risk == .high)
    }

    @Test("For memory candidate")
    func forMemory() {
        let a = factory.forMemoryCandidate(memoryID: "m1", summary: "User preference")
        #expect(a.kind == .memoryCandidate)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Expiration Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Approval Expiration")
struct ApprovalExpirationTests {

    @Test("Default TTLs")
    func defaultTTLs() {
        let p = ApprovalExpirationPolicy.default
        #expect(p.ttl(for: .medium) == 3600)
        #expect(p.ttl(for: .high) == 900)
        #expect(p.ttl(for: .critical) == 300)
    }

    @Test("Future expiry is not expired")
    func futureNotExpired() {
        let a = makePendingApproval(expiresAt: Date().addingTimeInterval(3600))
        #expect(!a.isExpired)
    }

    @Test("Past expiry is expired")
    func pastIsExpired() {
        let a = makePendingApproval(expiresAt: Date().addingTimeInterval(-100))
        #expect(a.isExpired)
    }

    @Test("No expiry is never expired")
    func noExpiryNeverExpired() {
        let a = makePendingApproval(expiresAt: nil)
        #expect(!a.isExpired)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Menu Bar Status Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Menu Bar Status")
struct MenuBarStatusTests {

    @Test("Status model encodes")
    func statusEncodes() throws {
        let s = MenuBarStatus(pendingCount: 3, highRiskPending: true, runnerActive: true, runnerPaused: false)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(MenuBarStatus.self, from: data)
        #expect(decoded.pendingCount == 3)
        #expect(decoded.highRiskPending)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Approval Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Unified Approval Store")
struct UnifiedApprovalStoreTests {

    @Test("Save and get")
    func saveAndGet() async throws {
        let store = InMemoryUnifiedApprovalStore()
        let a = makePendingApproval(id: "a1")
        await store.save(a)
        let got = await store.get(id: "a1")
        #expect(got?.id == "a1")
    }

    @Test("List pending excludes resolved")
    func pendingExcludesResolved() async throws {
        let store = InMemoryUnifiedApprovalStore()
        var a = makePendingApproval(id: "a1")
        await store.save(a)
        a = a.resolved(status: .approved, resolvedAt: Date())
        await store.update(a)
        let pending = await store.listPending()
        #expect(pending.isEmpty)
    }

    @Test("List pending excludes expired")
    func pendingExcludesExpired() async throws {
        let store = InMemoryUnifiedApprovalStore()
        let a = makePendingApproval(id: "a1", expiresAt: Date().addingTimeInterval(-100))
        await store.save(a)
        let pending = await store.listPending()
        #expect(pending.isEmpty)
    }
}
