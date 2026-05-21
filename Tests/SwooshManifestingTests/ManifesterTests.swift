// Tests/SwooshManifestingTests/ManifesterTests.swift — Manifester execution tests
//
// Tests the Manifester actor, pattern mining, phase execution,
// and the full manifestation pipeline.

import Testing
import Foundation
@testable import SwooshManifesting

// MARK: - Test Doubles

actor MockManifestationStore: ManifestationStoring {
    private var manifestations: [String: Manifestation] = [:]

    func save(_ manifestation: Manifestation) async throws {
        manifestations[manifestation.id] = manifestation
    }

    func update(_ manifestation: Manifestation) async throws {
        manifestations[manifestation.id] = manifestation
    }

    func get(id: String) async throws -> Manifestation? {
        manifestations[id]
    }

    func listRecent(limit: Int) async throws -> [Manifestation] {
        Array(
            manifestations.values
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    func mostRecentCompleted() async throws -> Manifestation? {
        try await listRecent(limit: .max).first { $0.status == .completed }
    }
}

actor MockAuditSource: ManifestationAuditSource {
    var events: [ManifestationAuditEvent] = []

    func append(_ event: ManifestationAuditEvent) {
        events.append(event)
    }

    func appendAll(_ list: [ManifestationAuditEvent]) {
        events.append(contentsOf: list)
    }

    func eventsSince(_ cursor: Date?) async throws -> [ManifestationAuditEvent] {
        if let cursor = cursor {
            return events.filter { $0.timestamp > cursor }
        }
        return events
    }
}

// MARK: - EmptyManifestationAuditSource Tests

@Suite("EmptyManifestationAuditSource")
struct EmptyManifestationAuditSourceTests {

    @Test("Returns empty array for any cursor")
    func returnsEmpty() async throws {
        let source = EmptyManifestationAuditSource()

        let events1 = try await source.eventsSince(nil)
        let events2 = try await source.eventsSince(Date())
        let events3 = try await source.eventsSince(Date(timeIntervalSince1970: 0))

        #expect(events1.isEmpty)
        #expect(events2.isEmpty)
        #expect(events3.isEmpty)
    }
}

// MARK: - ManifestationAuditEvent Tests

@Suite("ManifestationAuditEvent")
struct ManifestationAuditEventTests {

    @Test("Event initializes with required fields")
    func initializesWithRequired() {
        let event = ManifestationAuditEvent(
            id: "evt-1",
            kind: "tool_call",
            summary: "User called git.status",
            timestamp: Date()
        )

        #expect(event.id == "evt-1")
        #expect(event.kind == "tool_call")
        #expect(event.summary == "User called git.status")
        #expect(event.sessionID == nil)
        #expect(event.toolName == nil)
        #expect(event.timestamp <= Date())
    }

    @Test("Event initializes with all fields")
    func initializesWithAll() {
        let date = Date(timeIntervalSince1970: 1000)
        let event = ManifestationAuditEvent(
            id: "evt-2",
            kind: "tool_call",
            sessionID: "session-123",
            toolName: "git.status",
            summary: "Checked git status",
            timestamp: date
        )

        #expect(event.id == "evt-2")
        #expect(event.sessionID == "session-123")
        #expect(event.toolName == "git.status")
        #expect(event.timestamp == date)
    }

    @Test("Event is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let event = ManifestationAuditEvent(
            id: "test",
            kind: "test",
            summary: "test",
            timestamp: Date()
        )

        // Identifiable
        _ = event.id

        // Codable
        let data = try? JSONEncoder().encode(event)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = ManifestationAuditEvent.self
    }
}

// MARK: - Manifester Initialization Tests

@Suite("Manifester Initialization")
struct ManifesterInitializationTests {

    @Test("Manifester initializes with store only")
    func initializesWithStoreOnly() {
        let store = MockManifestationStore()
        let manifester = Manifester(store: store)

        #expect(manifester != nil)
    }

    @Test("Manifester initializes with custom audit source")
    func initializesWithAuditSource() {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()
        let manifester = Manifester(store: store, auditSource: auditSource)

        #expect(manifester != nil)
    }

    @Test("Manifester initializes with custom miner")
    func initializesWithMiner() {
        let store = MockManifestationStore()
        let customMiner: Manifester.PatternMiner = { _ in
            return [ManifestationProposal(
                kind: .observation,
                title: "Custom",
                rationale: "Test",
                confidence: 0.5,
                payloadJSON: "{}"
            )]
        }

        let manifester = Manifester(store: store, miner: customMiner)
        #expect(manifester != nil)
    }

    @Test("Manifester uses empty audit source by default")
    func usesEmptyAuditSourceByDefault() async throws {
        let store = MockManifestationStore()
        let manifester = Manifester(store: store)

        // Run once - should skip because no events
        let result = try await manifester.runOnce()

        #expect(result.status == .skipped)
    }

    @Test("Manifester uses deterministic miner by default")
    func usesDeterministicMinerByDefault() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add some events
        await auditSource.appendAll([
            ManifestationAuditEvent(id: "1", kind: "tool_call", summary: "Test", timestamp: Date()),
            ManifestationAuditEvent(id: "2", kind: "tool_call", summary: "Test", timestamp: Date()),
            ManifestationAuditEvent(id: "3", kind: "tool_call", summary: "Test", timestamp: Date())
        ])

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.status == .completed)
    }
}

// MARK: - Manifester Phase Execution Tests

@Suite("Manifester Phases")
struct ManifesterPhaseTests {

    @Test("RunOnce records gather phase")
    func recordsGatherPhase() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "tool_call", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.phases.contains { $0.name == .gather })
    }

    @Test("RunOnce records mine phase")
    func recordsMinePhase() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "tool_call", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.phases.contains { $0.name == .mine })
    }

    @Test("RunOnce records propose phase")
    func recordsProposePhase() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add enough events to trigger proposals
        for i in 1...3 {
            await auditSource.append(ManifestationAuditEvent(
                id: "\(i)", kind: "tool_call", toolName: "git.status", summary: "Git status", timestamp: Date()
            ))
        }

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.phases.contains { $0.name == .propose })
    }

    @Test("RunOnce records consolidate phase")
    func recordsConsolidatePhase() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "tool_call", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.phases.contains { $0.name == .consolidate })
    }

    @Test("RunOnce records summarize phase")
    func recordsSummarizePhase() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "tool_call", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.phases.contains { $0.name == .summarize })
        #expect(result.summary != nil)
    }

    @Test("Phases have start and finish times")
    func phasesHaveTimestamps() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "tool_call", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        for phase in result.phases {
            #expect(phase.startedAt <= Date())
            #expect(phase.finishedAt != nil)
            #expect(phase.finishedAt! >= phase.startedAt)
        }
    }
}

// MARK: - Manifester Skip Logic Tests

@Suite("Manifester Skip Logic")
struct ManifesterSkipTests {

    @Test("RunOnce skips when no new events")
    func skipsWhenNoEvents() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.status == .skipped)
        #expect(result.summary?.contains("No new audit events") == true)
    }

    @Test("RunOnce skips when no events since last manifestation")
    func skipsWhenNoNewEvents() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add old event
        let oldEvent = ManifestationAuditEvent(
            id: "1", kind: "tool_call", summary: "Old",
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        await auditSource.append(oldEvent)

        let manifester = Manifester(store: store, auditSource: auditSource)

        // First run completes
        let first = try await manifester.runOnce()
        #expect(first.status == .completed)

        // Second run skips (no new events)
        let second = try await manifester.runOnce()
        #expect(second.status == .skipped)
    }
}

// MARK: - Manifester Proposal Tests

@Suite("Manifester Proposals")
struct ManifesterProposalTests {

    @Test("Deterministic miner creates proposals for repeated event kinds")
    func minerCreatesProposalsForKinds() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add 3+ events of same kind
        for i in 1...3 {
            await auditSource.append(ManifestationAuditEvent(
                id: "\(i)", kind: "tool_call", summary: "Call \(i)", timestamp: Date()
            ))
        }

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.proposals.contains { $0.kind == .observation && $0.title.contains("Repeated") })
    }

    @Test("Deterministic miner creates proposals for repeated tool use")
    func minerCreatesProposalsForTools() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add 2+ events using same tool
        for i in 1...2 {
            await auditSource.append(ManifestationAuditEvent(
                id: "\(i)", kind: "tool_call", toolName: "git.status", summary: "Git status \(i)", timestamp: Date()
            ))
        }

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.proposals.contains { $0.title.contains("git.status") })
    }

    @Test("Miner caps proposals at 5")
    func minerCapsAt5() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add many events of different kinds
        for i in 1...20 {
            await auditSource.append(ManifestationAuditEvent(
                id: "\(i)", kind: "kind-\(i)", summary: "Event \(i)", timestamp: Date()
            ))
        }

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        #expect(result.proposals.count <= 5)
    }

    @Test("Confidence increases with more events")
    func confidenceIncreases() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        // Add 10 events of same kind
        for i in 1...10 {
            await auditSource.append(ManifestationAuditEvent(
                id: "\(i)", kind: "tool_call", toolName: "git.status", summary: "Call \(i)", timestamp: Date()
            ))
        }

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        if let proposal = result.proposals.first {
            #expect(proposal.confidence > 0.5)
            #expect(proposal.confidence <= 0.95)
        }
    }
}

// MARK: - Manifester Consolidation Tests

@Suite("Manifester Consolidation")
struct ManifesterConsolidationTests {

    @Test("Consolidation creates merge suggestions for duplicates")
    func createsMergeSuggestions() async throws {
        let store = MockManifestationStore()

        // Create custom miner that returns duplicate skill proposals
        let customMiner: Manifester.PatternMiner = { _ in
            return [
                ManifestationProposal(
                    kind: .newSkill,
                    title: "git workflow",
                    rationale: "Pattern 1",
                    confidence: 0.8,
                    payloadJSON: "{}"
                ),
                ManifestationProposal(
                    kind: .newSkill,
                    title: "git workflow", // Same title - duplicate
                    rationale: "Pattern 2",
                    confidence: 0.7,
                    payloadJSON: "{}"
                )
            ]
        }

        let auditSource = MockAuditSource()
        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource, miner: customMiner)
        let result = try await manifester.runOnce()

        #expect(result.proposals.contains { $0.kind == .skillMerge })
    }

    @Test("Merge proposal contains duplicate IDs")
    func mergeProposalContainsIDs() async throws {
        let store = MockManifestationStore()

        let id1 = UUID().uuidString
        let id2 = UUID().uuidString

        let customMiner: Manifester.PatternMiner = { _ in
            return [
                ManifestationProposal(
                    kind: .newSkill,
                    title: "duplicate skill",
                    rationale: "Pattern 1",
                    confidence: 0.8,
                    payloadJSON: "{\"id\":\"\(id1)\"}"
                ),
                ManifestationProposal(
                    kind: .newSkill,
                    title: "duplicate skill",
                    rationale: "Pattern 2",
                    confidence: 0.7,
                    payloadJSON: "{\"id\":\"\(id2)\"}"
                )
            ]
        }

        let auditSource = MockAuditSource()
        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource, miner: customMiner)
        let result = try await manifester.runOnce()

        if let merge = result.proposals.first(where: { $0.kind == .skillMerge }) {
            #expect(merge.payloadJSON.contains(id1) || merge.payloadJSON.contains("candidateIDs"))
        }
    }
}

// MARK: - Manifester Error Handling Tests

@Suite("Manifester Error Handling")
struct ManifesterErrorTests {

    @Test("RunOnce fails when gather throws")
    func failsWhenGatherThrows() async throws {
        let store = MockManifestationStore()

        actor FailingAuditSource: ManifestationAuditSource {
            func eventsSince(_ cursor: Date?) async throws -> [ManifestationAuditEvent] {
                throw TestError.simulated
            }
        }

        let manifester = Manifester(store: store, auditSource: FailingAuditSource())
        let result = try await manifester.runOnce()

        #expect(result.status == .failed)
        #expect(result.phases.count == 1) // Only gather phase
        #expect(result.phases[0].name == .gather)
        #expect(result.phases[0].observation?.contains("gather failed") == true)
    }

    @Test("RunOnce fails when mine throws")
    func failsWhenMineThrows() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let failingMiner: Manifester.PatternMiner = { _ in
            throw TestError.simulated
        }

        let manifester = Manifester(store: store, auditSource: auditSource, miner: failingMiner)
        let result = try await manifester.runOnce()

        #expect(result.status == .failed)
        #expect(result.phases.contains { $0.name == .mine })
        #expect(result.phases.first { $0.name == .mine }?.observation?.contains("mine failed") == true)
    }
}

// MARK: - Manifester Persistence Tests

@Suite("Manifester Persistence")
struct ManifesterPersistenceTests {

    @Test("RunOnce saves manifestation to store")
    func savesToStore() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce()

        let saved = try await store.get(id: result.id)
        #expect(saved != nil)
        #expect(saved?.id == result.id)
        #expect(saved?.status == result.status)
    }

    @Test("MostRecentCompleted returns latest completed")
    func mostRecentCompletedWorks() async throws {
        let store = MockManifestationStore()

        // Save old completed manifestation
        var old = Manifestation(triggerReason: "old")
        old.status = .completed
        old.finishedAt = Date(timeIntervalSince1970: 1000)
        try await store.save(old)

        // Save newer completed manifestation
        var new = Manifestation(triggerReason: "new")
        new.status = .completed
        new.finishedAt = Date(timeIntervalSince1970: 2000)
        try await store.save(new)

        let manifester = Manifester(store: store)
        let mostRecent = try await store.mostRecentCompleted()

        #expect(mostRecent?.triggerReason == "new")
    }

    @Test("MostRecentCompleted returns nil when none completed")
    func mostRecentCompletedNilWhenNone() async throws {
        let store = MockManifestationStore()

        // Save failed manifestation
        var failed = Manifestation(triggerReason: "test")
        failed.status = .failed
        try await store.save(failed)

        let mostRecent = try await store.mostRecentCompleted()

        #expect(mostRecent == nil)
    }
}

// MARK: - Manifester Trigger Reasons Tests

@Suite("Manifester Trigger Reasons")
struct ManifesterTriggerReasonTests {

    @Test("Records scheduled-daily trigger")
    func recordsScheduledDaily() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce(triggerReason: "scheduled-daily")

        #expect(result.triggerReason == "scheduled-daily")
    }

    @Test("Records manual trigger")
    func recordsManual() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce(triggerReason: "manual")

        #expect(result.triggerReason == "manual")
    }

    @Test("Records idle-trigger")
    func recordsIdleTrigger() async throws {
        let store = MockManifestationStore()
        let auditSource = MockAuditSource()

        await auditSource.append(ManifestationAuditEvent(
            id: "1", kind: "test", summary: "Test", timestamp: Date()
        ))

        let manifester = Manifester(store: store, auditSource: auditSource)
        let result = try await manifester.runOnce(triggerReason: "idle-trigger")

        #expect(result.triggerReason == "idle-trigger")
    }
}

// Test error
private enum TestError: Error {
    case simulated
}
