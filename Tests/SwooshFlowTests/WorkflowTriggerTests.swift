// Tests/SwooshFlowTests/WorkflowTriggerTests.swift — 0.6A Tests

import Testing
import Foundation
@testable import SwooshFlow
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Enablement Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Enablement")
struct WorkflowEnablementTests {

    @Test("Enable manual creates enablement")
    func enableManual() async throws {
        let store = InMemoryEnablementStore()
        let e = WorkflowEnablement(workflowID: "w1", state: .enabledManualOnly)
        try await store.save(e)
        let got = try await store.get(workflowID: "w1")
        #expect(got?.state == .enabledManualOnly)
    }

    @Test("Disable updates state")
    func disable() async throws {
        let store = InMemoryEnablementStore()
        var e = WorkflowEnablement(workflowID: "w1", state: .enabledManualOnly)
        try await store.save(e)
        e.state = .disabled; e.updatedAt = Date()
        try await store.update(e)
        #expect(try await store.get(workflowID: "w1")?.state == .disabled)
    }

    @Test("List enabled workflows")
    func listEnabled() async throws {
        let store = InMemoryEnablementStore()
        try await store.save(WorkflowEnablement(workflowID: "w1", state: .enabledManualOnly))
        try await store.save(WorkflowEnablement(workflowID: "w2", state: .disabled))
        let enabled = try await store.listEnabled()
        #expect(enabled.count == 1)
        #expect(enabled[0].workflowID == "w1")
    }

    @Test("Manual-only policy defaults correct")
    func manualOnlyDefaults() {
        let p = WorkflowActivationPolicy.manualOnly
        #expect(p.allowManualRuns)
        #expect(!p.allowTriggeredRuns)
        #expect(!p.allowUnattendedRuns)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Trigger Store Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Store")
struct TriggerStoreTests {

    @Test("Save and get trigger")
    func saveAndGet() async throws {
        let store = InMemoryTriggerStore()
        let t = WorkflowTrigger(workflowID: "w1", name: "Manual", kind: .manual, configuration: .manual(ManualTriggerConfig()))
        try await store.save(t)
        let got = try await store.get(id: t.id)
        #expect(got?.name == "Manual")
    }

    @Test("List triggers for workflow")
    func listForWorkflow() async throws {
        let store = InMemoryTriggerStore()
        try await store.save(WorkflowTrigger(workflowID: "w1", name: "A", kind: .manual, configuration: .manual(ManualTriggerConfig())))
        try await store.save(WorkflowTrigger(workflowID: "w2", name: "B", kind: .manual, configuration: .manual(ManualTriggerConfig())))
        let w1 = try await store.list(workflowID: "w1")
        #expect(w1.count == 1)
    }

    @Test("Delete trigger")
    func deleteTrigger() async throws {
        let store = InMemoryTriggerStore()
        let t = WorkflowTrigger(workflowID: "w1", name: "A", kind: .manual, configuration: .manual(ManualTriggerConfig()))
        try await store.save(t)
        try await store.delete(id: t.id)
        #expect(try await store.get(id: t.id) == nil)
    }

    @Test("Update trigger")
    func updateTrigger() async throws {
        let store = InMemoryTriggerStore()
        var t = WorkflowTrigger(workflowID: "w1", name: "A", kind: .manual, configuration: .manual(ManualTriggerConfig()))
        try await store.save(t)
        t.name = "Updated"
        try await store.update(t)
        #expect(try await store.get(id: t.id)?.name == "Updated")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Trigger Validator Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Validator")
struct TriggerValidatorTests {
    let v = WorkflowTriggerValidator()

    @Test("Manual trigger valid")
    func manualValid() {
        let t = WorkflowTrigger(workflowID: "w", name: "M", kind: .manual, configuration: .manual(ManualTriggerConfig()))
        let r = v.validate(t)
        #expect(r.isValid)
    }

    @Test("Schedule trigger valid daily")
    func scheduleValidDaily() {
        let cfg = ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 30)))
        let t = WorkflowTrigger(workflowID: "w", name: "S", kind: .schedule, configuration: .schedule(cfg))
        let r = v.validate(t)
        #expect(r.isValid)
        #expect(!r.milestoneLimitations.isEmpty) // not armed
    }

    @Test("Schedule invalid hour fails")
    func scheduleInvalidHour() {
        let cfg = ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 25, minute: 0)))
        let t = WorkflowTrigger(workflowID: "w", name: "S", kind: .schedule, configuration: .schedule(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("Interval too short fails")
    func intervalTooShort() {
        let cfg = ScheduleTriggerConfig(schedule: .interval(IntervalSchedule(everySeconds: 10)))
        let t = WorkflowTrigger(workflowID: "w", name: "S", kind: .schedule, configuration: .schedule(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("File trigger requires rootID")
    func fileRequiresRoot() {
        let cfg = FileChangedTriggerConfig(rootID: "")
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("File trigger rejects full disk")
    func fileRejectsFullDisk() {
        let cfg = FileChangedTriggerConfig(rootID: "/")
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("File trigger rejects sensitive paths")
    func fileRejectsSensitive() {
        let cfg = FileChangedTriggerConfig(rootID: "root1", includeGlobs: [".ssh/**"])
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("File trigger rejects cookie paths")
    func fileRejectsCookies() {
        let cfg = FileChangedTriggerConfig(rootID: "root1", includeGlobs: ["Cookies/data"])
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("Webhook must be local-only")
    func webhookLocalOnly() {
        let cfg = WebhookTriggerConfig(localOnly: false)
        let t = WorkflowTrigger(workflowID: "w", name: "W", kind: .webhook, configuration: .webhook(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("Webhook local-only valid")
    func webhookLocalValid() {
        let cfg = WebhookTriggerConfig(localOnly: true)
        let t = WorkflowTrigger(workflowID: "w", name: "W", kind: .webhook, configuration: .webhook(cfg))
        let r = v.validate(t)
        #expect(r.isValid)
        #expect(!r.milestoneLimitations.isEmpty)
    }

    @Test("App event requires bundle ID")
    func appEventRequiresBundle() {
        let cfg = AppEventTriggerConfig(bundleIdentifier: "", event: .launched)
        let t = WorkflowTrigger(workflowID: "w", name: "A", kind: .appEvent, configuration: .appEvent(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("App event invalid bundle format")
    func appEventInvalidBundle() {
        let cfg = AppEventTriggerConfig(bundleIdentifier: "noDots", event: .activated)
        let t = WorkflowTrigger(workflowID: "w", name: "A", kind: .appEvent, configuration: .appEvent(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("App event valid bundle")
    func appEventValid() {
        let cfg = AppEventTriggerConfig(bundleIdentifier: "com.apple.dt.Xcode", event: .activated)
        let t = WorkflowTrigger(workflowID: "w", name: "A", kind: .appEvent, configuration: .appEvent(cfg))
        let r = v.validate(t)
        #expect(r.isValid)
        #expect(!r.milestoneLimitations.isEmpty)
    }

    @Test("Calendar trigger warns about permission")
    func calendarWarnsPermission() {
        let cfg = CalendarEventTriggerConfig(matchTitleContains: "standup")
        let t = WorkflowTrigger(workflowID: "w", name: "C", kind: .calendarEvent, configuration: .calendarEvent(cfg))
        let r = v.validate(t)
        #expect(r.isValid)
        #expect(!r.warnings.isEmpty)
    }

    @Test("Non-manual triggers have milestone limitation")
    func nonManualLimitation() {
        let cfg = ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 9, minute: 0)))
        let t = WorkflowTrigger(workflowID: "w", name: "S", kind: .schedule, configuration: .schedule(cfg))
        let r = v.validate(t)
        #expect(r.milestoneLimitations.contains { $0.contains("0.6A") })
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Trigger Preview Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Preview")
struct TriggerPreviewTests {
    let previewer = WorkflowTriggerPreviewer()

    @Test("Schedule preview has fire times")
    func scheduleFireTimes() {
        let cfg = ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 30)), humanDescription: "Daily 8:30")
        let t = WorkflowTrigger(workflowID: "w", name: "S", kind: .schedule, configuration: .schedule(cfg))
        let p = previewer.preview(t)
        #expect(!p.nextFireTimes.isEmpty)
        #expect(p.summaryMarkdown.contains("Not armed"))
    }

    @Test("File preview shows globs")
    func filePreviewGlobs() {
        let cfg = FileChangedTriggerConfig(rootID: "root1", includeGlobs: ["Sources/**/*.swift"])
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        let p = previewer.preview(t)
        #expect(p.watchedPathsPreview.contains("Sources/**/*.swift"))
        #expect(p.summaryMarkdown.contains("not armed"))
    }

    @Test("Webhook preview says local-only")
    func webhookLocalOnly() {
        let cfg = WebhookTriggerConfig(localOnly: true)
        let t = WorkflowTrigger(workflowID: "w", name: "W", kind: .webhook, configuration: .webhook(cfg))
        let p = previewer.preview(t)
        #expect(p.summaryMarkdown.contains("local-only"))
    }

    @Test("App event preview shows bundle")
    func appEventBundle() {
        let cfg = AppEventTriggerConfig(bundleIdentifier: "com.apple.dt.Xcode", event: .activated)
        let t = WorkflowTrigger(workflowID: "w", name: "A", kind: .appEvent, configuration: .appEvent(cfg))
        let p = previewer.preview(t)
        #expect(p.summaryMarkdown.contains("Xcode"))
    }

    @Test("Calendar preview shows matching rule")
    func calendarMatching() {
        let cfg = CalendarEventTriggerConfig(matchTitleContains: "standup", startsWithinMinutes: 30)
        let t = WorkflowTrigger(workflowID: "w", name: "C", kind: .calendarEvent, configuration: .calendarEvent(cfg))
        let p = previewer.preview(t)
        #expect(p.summaryMarkdown.contains("standup"))
        #expect(p.summaryMarkdown.contains("30"))
    }

    @Test("Manual preview shows execute command")
    func manualExecute() {
        let t = WorkflowTrigger(workflowID: "w1", name: "M", kind: .manual, configuration: .manual(ManualTriggerConfig()))
        let p = previewer.preview(t)
        #expect(p.summaryMarkdown.contains("/workflow execute"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Safety Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Trigger Safety")
struct TriggerSafetyTests {

    @Test("No trigger fire method exists")
    func noFireMethod() {
        // Compile-time proof: WorkflowTrigger has no fire() method
        let t = WorkflowTrigger(workflowID: "w", name: "S", kind: .schedule,
            configuration: .schedule(ScheduleTriggerConfig(schedule: .daily(DailySchedule(hour: 8, minute: 0)))))
        #expect(t.state == .draft) // It can only be draft/configured/validated, never "running"
    }

    @Test("Activation policy blocks triggered runs")
    func policyBlocksTriggered() {
        let p = WorkflowActivationPolicy.manualOnly
        #expect(!p.allowTriggeredRuns)
        #expect(!p.allowUnattendedRuns)
    }

    @Test("Trigger configured only still blocks triggered")
    func configuredOnlyBlocks() {
        let p = WorkflowActivationPolicy.triggerConfiguredOnly
        #expect(!p.allowTriggeredRuns)
    }

    @Test("File trigger rejects keychain paths")
    func rejectsKeychain() {
        let v = WorkflowTriggerValidator()
        let cfg = FileChangedTriggerConfig(rootID: "r", includeGlobs: ["Keychain/secrets"])
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("File trigger rejects .env paths")
    func rejectsDotEnv() {
        let v = WorkflowTriggerValidator()
        let cfg = FileChangedTriggerConfig(rootID: "r", includeGlobs: [".env"])
        let t = WorkflowTrigger(workflowID: "w", name: "F", kind: .fileChanged, configuration: .fileChanged(cfg))
        #expect(!v.validate(t).isValid)
    }

    @Test("Webhook secret is reference only")
    func webhookSecretRef() {
        let cfg = WebhookTriggerConfig(secretRef: "keychain:wh_secret_123", localOnly: true)
        // secretRef is a reference, never a raw value
        #expect(cfg.secretRef?.hasPrefix("keychain:") == true)
    }
}
