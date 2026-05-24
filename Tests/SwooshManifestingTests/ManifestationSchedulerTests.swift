// Tests/SwooshManifestingTests/ManifestationSchedulerTests.swift — 0.1A
//
// Pins the policy decisions of `ManifestationScheduler.tick`:
//   - cooldown blocks even when interval is satisfied
//   - interval alone fires with reason "scheduled-daily"
//   - idle alone fires with reason "idle-trigger"
//   - both → "idle+interval"
//   - active Focus mode in `skipDuringFocus` blocks regardless
//   - no source events ⇒ runOnce skips ⇒ store still reflects the skip
//
// The scheduler decides; the Manifester does the work. We feed a
// fake-time `now` parameter + an idle/Focus override so we don't depend
// on the wall clock or system idle reader.

import Testing
import Foundation
@testable import SwooshManifesting

private actor FakeAuditSource: ManifestationAuditSource {
    private let events: [ManifestationAuditEvent]
    init(events: [ManifestationAuditEvent] = []) {
        self.events = events
    }
    func eventsSince(_ cursor: Date?) async throws -> [ManifestationAuditEvent] {
        guard let cursor else { return events }
        return events.filter { $0.timestamp > cursor }
    }
}

/// Build a store that already has one `.completed` manifestation
/// finishing `secondsAgo` before `now`. Lets each test express its own
/// "elapsed since last pass" without juggling real `Date()`s.
private func storeWithLastCompletion(
    secondsAgo: TimeInterval,
    now: Date
) async throws -> InMemoryManifestationStore {
    let store = InMemoryManifestationStore()
    var seed = Manifestation(
        triggerReason: "seed",
        startedAt: now.addingTimeInterval(-secondsAgo - 1)
    )
    seed.status = .completed
    seed.finishedAt = now.addingTimeInterval(-secondsAgo)
    try await store.save(seed)
    return store
}

@Suite("ManifestationScheduler — policy")
struct ManifestationSchedulerPolicyTests {

    @Test("Cooldown blocks even when interval is satisfied")
    func cooldownBlocks() async throws {
        let now = Date()
        // Last pass finished 30s ago. Cooldown is 60s.
        let store = try await storeWithLastCompletion(secondsAgo: 30, now: now)
        let manifester = Manifester(store: store, auditSource: FakeAuditSource())
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 10,    // would otherwise fire
                idleThreshold: nil,
                skipDuringFocus: [],
                minimumCooldown: 60     // but cooldown still blocks
            )
        )
        let result = try await scheduler.tick(now: now)
        #expect(result == nil)
    }

    @Test("Interval-only — fires with reason scheduled-daily")
    func intervalOnlyFires() async throws {
        let now = Date()
        let store = try await storeWithLastCompletion(secondsAgo: 7200, now: now)
        // One audit event so the run reaches `.completed` instead of `.skipped`.
        let event = ManifestationAuditEvent(
            id: "e1", kind: "tool_call",
            summary: "did a thing", timestamp: now.addingTimeInterval(-60)
        )
        let manifester = Manifester(store: store, auditSource: FakeAuditSource(events: [event]))
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 3600, // 2h elapsed > 1h interval
                idleThreshold: nil,
                skipDuringFocus: [],
                minimumCooldown: 60
            )
        )
        let result = try await scheduler.tick(now: now)
        let manifestation = try #require(result)
        #expect(manifestation.triggerReason == "scheduled-daily")
        #expect(manifestation.status == .completed)
    }

    @Test("Idle-only — fires with reason idle-trigger")
    func idleOnlyFires() async throws {
        let now = Date()
        // Interval NOT satisfied yet — last pass was 5 minutes ago and
        // policy.minimumInterval is 1 hour. But idle is satisfied.
        let store = try await storeWithLastCompletion(secondsAgo: 5 * 60, now: now)
        let event = ManifestationAuditEvent(
            id: "e1", kind: "tool_call",
            summary: "did a thing", timestamp: now.addingTimeInterval(-30)
        )
        let manifester = Manifester(store: store, auditSource: FakeAuditSource(events: [event]))
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 3600,
                idleThreshold: 60,
                skipDuringFocus: [],
                minimumCooldown: 60   // 5min elapsed > 60s cooldown
            )
        )
        let result = try await scheduler.tick(now: now, idleSeconds: 600)
        let manifestation = try #require(result)
        #expect(manifestation.triggerReason == "idle-trigger")
    }

    @Test("Both interval and idle satisfied — reason idle+interval")
    func bothSatisfied() async throws {
        let now = Date()
        let store = try await storeWithLastCompletion(secondsAgo: 7200, now: now)
        let event = ManifestationAuditEvent(
            id: "e1", kind: "tool_call",
            summary: "did a thing", timestamp: now.addingTimeInterval(-30)
        )
        let manifester = Manifester(store: store, auditSource: FakeAuditSource(events: [event]))
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 3600,
                idleThreshold: 60,
                skipDuringFocus: [],
                minimumCooldown: 60
            )
        )
        let result = try await scheduler.tick(now: now, idleSeconds: 600)
        let manifestation = try #require(result)
        #expect(manifestation.triggerReason == "idle+interval")
    }

    @Test("Active Focus in skipDuringFocus blocks regardless")
    func focusBlocks() async throws {
        let now = Date()
        let store = try await storeWithLastCompletion(secondsAgo: 7200, now: now)
        let manifester = Manifester(store: store, auditSource: FakeAuditSource())
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 60,
                idleThreshold: 60,
                skipDuringFocus: ["com.apple.donotdisturb.mode.work"],
                minimumCooldown: 1
            )
        )
        let result = try await scheduler.tick(
            now: now,
            idleSeconds: 600,
            activeFocus: "com.apple.donotdisturb.mode.work"
        )
        #expect(result == nil)
    }

    @Test("Neither idle nor interval satisfied — no fire")
    func noTriggers() async throws {
        let now = Date()
        let store = try await storeWithLastCompletion(secondsAgo: 5 * 60, now: now)
        let manifester = Manifester(store: store, auditSource: FakeAuditSource())
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 3600,
                idleThreshold: 600,
                skipDuringFocus: [],
                minimumCooldown: 1
            )
        )
        let result = try await scheduler.tick(now: now, idleSeconds: 30)
        #expect(result == nil)
    }

    @Test("First-ever run — no prior completion lets interval fire immediately")
    func firstRun() async throws {
        let now = Date()
        let store = InMemoryManifestationStore() // empty
        let event = ManifestationAuditEvent(
            id: "e1", kind: "tool_call",
            summary: "did a thing", timestamp: now.addingTimeInterval(-30)
        )
        let manifester = Manifester(store: store, auditSource: FakeAuditSource(events: [event]))
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 60,
                idleThreshold: nil,
                skipDuringFocus: [],
                minimumCooldown: 60
            )
        )
        let result = try await scheduler.tick(now: now)
        let manifestation = try #require(result)
        #expect(manifestation.triggerReason == "scheduled-daily")
    }

    @Test("Run with no audit events produces a .skipped pass")
    func noEventsProducesSkipped() async throws {
        let now = Date()
        let store = try await storeWithLastCompletion(secondsAgo: 7200, now: now)
        let manifester = Manifester(store: store, auditSource: FakeAuditSource(events: []))
        let scheduler = ManifestationScheduler(
            manifester: manifester,
            store: store,
            policy: ManifestationPolicy(
                minimumInterval: 3600,
                idleThreshold: nil,
                skipDuringFocus: [],
                minimumCooldown: 60
            )
        )
        let result = try await scheduler.tick(now: now)
        let manifestation = try #require(result)
        #expect(manifestation.status == .skipped)
        #expect(manifestation.triggerReason == "scheduled-daily")
    }
}
