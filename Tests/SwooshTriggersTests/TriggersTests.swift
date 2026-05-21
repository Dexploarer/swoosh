// Tests/SwooshTriggersTests/TriggersTests.swift — SwooshTriggers
//
// Covers SwooshTrigger data model, TriggerEvent / TriggerAction enum
// payloads, TriggerRegistry actor lifecycle (register / remove /
// enable / disable / markFired), and Codable round-trips.

import Testing
import Foundation
@testable import SwooshTriggers

// MARK: - SwooshTrigger model

@Suite("SwooshTrigger Model")
struct SwooshTriggerModelTests {

    private func base(_ name: String = "t") -> SwooshTrigger {
        SwooshTrigger(name: name, event: .manual, action: .notify(title: "hi", body: "yo"))
    }

    @Test("Default initialization")
    func defaults() {
        let t = base()
        #expect(t.isEnabled == true)
        #expect(t.fireCount == 0)
        #expect(t.lastFired == nil)
    }

    @Test("Custom fields preserved")
    func customFields() {
        let id = UUID()
        let date = Date()
        let t = SwooshTrigger(
            id: id, name: "n",
            event: .interval(seconds: 30),
            action: .agentRun(prompt: "hi", modelRoute: nil),
            isEnabled: false, lastFired: date, fireCount: 5
        )
        #expect(t.id == id)
        #expect(t.name == "n")
        #expect(t.isEnabled == false)
        #expect(t.fireCount == 5)
        #expect(t.lastFired == date)
    }
}

// MARK: - TriggerEvent

@Suite("TriggerEvent Codable")
struct TriggerEventCodableTests {

    private func roundTrip(_ event: TriggerEvent) throws -> TriggerEvent {
        let data = try JSONEncoder().encode(event)
        return try JSONDecoder().decode(TriggerEvent.self, from: data)
    }

    @Test("cron round-trips")
    func cron() throws {
        let event = TriggerEvent.cron(expression: "0 9 * * 1-5")
        if case .cron(let expr) = try roundTrip(event) {
            #expect(expr == "0 9 * * 1-5")
        } else { Issue.record("wrong case") }
    }

    @Test("naturalLanguage round-trips")
    func naturalLanguage() throws {
        let event = TriggerEvent.naturalLanguage(schedule: "every weekday at 9am")
        if case .naturalLanguage(let s) = try roundTrip(event) {
            #expect(s == "every weekday at 9am")
        } else { Issue.record("wrong case") }
    }

    @Test("interval round-trips")
    func interval() throws {
        let event = TriggerEvent.interval(seconds: 60)
        if case .interval(let s) = try roundTrip(event) {
            #expect(s == 60)
        } else { Issue.record("wrong case") }
    }

    @Test("fileChanged round-trips")
    func fileChanged() throws {
        let event = TriggerEvent.fileChanged(path: "/tmp/file")
        if case .fileChanged(let p) = try roundTrip(event) {
            #expect(p == "/tmp/file")
        } else { Issue.record("wrong case") }
    }

    @Test("appLaunched round-trips")
    func appLaunched() throws {
        let event = TriggerEvent.appLaunched(bundleID: "com.apple.Safari")
        if case .appLaunched(let bid) = try roundTrip(event) {
            #expect(bid == "com.apple.Safari")
        } else { Issue.record("wrong case") }
    }

    @Test("screenLocked / screenUnlocked round-trip")
    func screenEvents() throws {
        if case .screenLocked = try roundTrip(.screenLocked) {} else { Issue.record() }
        if case .screenUnlocked = try roundTrip(.screenUnlocked) {} else { Issue.record() }
    }

    @Test("manual round-trips")
    func manual() throws {
        if case .manual = try roundTrip(.manual) {} else { Issue.record("manual") }
    }

    @Test("webhookReceived round-trips")
    func webhook() throws {
        let event = TriggerEvent.webhookReceived(path: "/hook")
        if case .webhookReceived(let p) = try roundTrip(event) {
            #expect(p == "/hook")
        } else { Issue.record("wrong case") }
    }

    @Test("batteryBelow round-trips with percent")
    func battery() throws {
        let event = TriggerEvent.batteryBelow(percent: 15)
        if case .batteryBelow(let p) = try roundTrip(event) {
            #expect(p == 15)
        } else { Issue.record("wrong case") }
    }
}

// MARK: - TriggerAction

@Suite("TriggerAction Codable")
struct TriggerActionCodableTests {

    private func roundTrip(_ action: TriggerAction) throws -> TriggerAction {
        let data = try JSONEncoder().encode(action)
        return try JSONDecoder().decode(TriggerAction.self, from: data)
    }

    @Test("agentRun round-trips with optional modelRoute")
    func agentRunWithRoute() throws {
        let action = TriggerAction.agentRun(prompt: "hi", modelRoute: "fast")
        if case .agentRun(let p, let r) = try roundTrip(action) {
            #expect(p == "hi")
            #expect(r == "fast")
        } else { Issue.record() }
    }

    @Test("agentRun round-trips with nil modelRoute")
    func agentRunNilRoute() throws {
        let action = TriggerAction.agentRun(prompt: "hi", modelRoute: nil)
        if case .agentRun(let p, let r) = try roundTrip(action) {
            #expect(p == "hi")
            #expect(r == nil)
        } else { Issue.record() }
    }

    @Test("workflowRun round-trips with UUID")
    func workflowRun() throws {
        let id = UUID()
        if case .workflowRun(let decoded) = try roundTrip(.workflowRun(workflowID: id)) {
            #expect(decoded == id)
        } else { Issue.record() }
    }

    @Test("notify round-trips")
    func notify() throws {
        if case .notify(let t, let b) = try roundTrip(.notify(title: "T", body: "B")) {
            #expect(t == "T"); #expect(b == "B")
        } else { Issue.record() }
    }
}

// MARK: - SwooshTrigger Codable

@Suite("SwooshTrigger Codable")
struct SwooshTriggerCodableTests {

    @Test("Round-trip preserves all fields")
    func roundTrip() throws {
        let original = SwooshTrigger(
            name: "morning brief",
            event: .everyWeekday(at: "09:00"),
            action: .agentRun(prompt: "Summarize my calendar", modelRoute: nil)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SwooshTrigger.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.isEnabled == original.isEnabled)
    }
}

// MARK: - TriggerRegistry

@Suite("TriggerRegistry")
struct TriggerRegistryTests {

    private func t(_ name: String) -> SwooshTrigger {
        SwooshTrigger(name: name, event: .manual, action: .notify(title: name, body: ""))
    }

    @Test("Empty registry")
    func empty() async {
        let r = TriggerRegistry()
        #expect(await r.all().isEmpty)
        #expect(await r.enabled().isEmpty)
    }

    @Test("Register and list")
    func registerAndList() async {
        let r = TriggerRegistry()
        await r.register(t("b"))
        await r.register(t("a"))
        let all = await r.all()
        #expect(all.count == 2)
        #expect(all[0].name == "a") // sorted by name
        #expect(all[1].name == "b")
    }

    @Test("Remove unregisters")
    func remove() async {
        let r = TriggerRegistry()
        let trig = t("x")
        await r.register(trig)
        await r.remove(trig.id)
        #expect(await r.all().isEmpty)
    }

    @Test("Remove unknown id is a no-op")
    func removeUnknown() async {
        let r = TriggerRegistry()
        await r.remove(UUID())
        #expect(await r.all().isEmpty)
    }

    @Test("Disable / enable toggles flag")
    func toggle() async {
        let r = TriggerRegistry()
        let trig = t("x")
        await r.register(trig)
        await r.disable(trig.id)
        #expect(await r.enabled().isEmpty)
        await r.enable(trig.id)
        #expect(await r.enabled().count == 1)
    }

    @Test("enabled() filters disabled")
    func enabledFilters() async {
        let r = TriggerRegistry()
        let on = t("on")
        var off = t("off"); off.isEnabled = false
        await r.register(on)
        await r.register(off)
        let enabled = await r.enabled()
        #expect(enabled.count == 1)
        #expect(enabled[0].name == "on")
    }

    @Test("markFired increments count and updates lastFired")
    func markFired() async {
        let r = TriggerRegistry()
        let trig = t("x")
        await r.register(trig)
        await r.markFired(trig.id)
        await r.markFired(trig.id)
        let stored = await r.all().first
        #expect(stored?.fireCount == 2)
        #expect(stored?.lastFired != nil)
    }

    @Test("markFired unknown id is a no-op")
    func markFiredUnknown() async {
        let r = TriggerRegistry()
        await r.markFired(UUID())
        #expect(await r.all().isEmpty)
    }
}
