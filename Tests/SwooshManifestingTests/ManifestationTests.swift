// Tests/SwooshManifestingTests/ManifestationTests.swift — Manifestation model tests
//
// Tests Manifestation, ManifestationStatus, ManifestationPhase, and
// ManifestationProposal data structures and their lifecycle.

import Testing
import Foundation
@testable import SwooshManifesting

// MARK: - ManifestationStatus Tests

@Suite("ManifestationStatus")
struct ManifestationStatusTests {

    @Test("All ManifestationStatus cases exist")
    func allCasesExist() {
        let statuses: [ManifestationStatus] = [.running, .completed, .failed, .skipped]
        #expect(statuses.count == 4)
    }

    @Test("ManifestationStatus is Codable and Sendable")
    func isCodableAndSendable() {
        let status: ManifestationStatus = .completed

        // Codable
        let data = try? JSONEncoder().encode(status)
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(ManifestationStatus.self, from: data!)
        #expect(decoded == .completed)

        // Sendable (compile-time check)
        let _: any Sendable.Type = ManifestationStatus.self
    }

    @Test("ManifestationStatus raw values are correct")
    func rawValuesCorrect() {
        #expect(ManifestationStatus.running.rawValue == "running")
        #expect(ManifestationStatus.completed.rawValue == "completed")
        #expect(ManifestationStatus.failed.rawValue == "failed")
        #expect(ManifestationStatus.skipped.rawValue == "skipped")
    }

    @Test("ManifestationStatus CaseIterable works")
    func caseIterableWorks() {
        let allCases = ManifestationStatus.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.running))
        #expect(allCases.contains(.completed))
        #expect(allCases.contains(.failed))
        #expect(allCases.contains(.skipped))
    }
}

// MARK: - ManifestationPhase Tests

@Suite("ManifestationPhase")
struct ManifestationPhaseTests {

    @Test("All PhaseName cases exist")
    func allPhaseNamesExist() {
        let names: [ManifestationPhase.PhaseName] = [.gather, .mine, .propose, .consolidate, .summarize]
        #expect(names.count == 5)
    }

    @Test("Phase initializes with defaults")
    func initializesWithDefaults() {
        let phase = ManifestationPhase(name: .gather)

        #expect(phase.name == .gather)
        #expect(phase.finishedAt == nil)
        #expect(phase.observation == nil)
        #expect(phase.id != "")
        #expect(phase.startedAt <= Date())
    }

    @Test("Phase initializes with custom start time")
    func initializesWithCustomTime() {
        let date = Date(timeIntervalSince1970: 1000)
        let phase = ManifestationPhase(name: .mine, startedAt: date)

        #expect(phase.name == .mine)
        #expect(phase.startedAt == date)
    }

    @Test("Phase can be finished")
    func canBeFinished() {
        var phase = ManifestationPhase(name: .propose)
        let finishTime = Date()

        phase.finishedAt = finishTime
        phase.observation = "Found 3 proposals"

        #expect(phase.finishedAt == finishTime)
        #expect(phase.observation == "Found 3 proposals")
    }

    @Test("Phase is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let phase = ManifestationPhase(name: .summarize)

        // Identifiable
        _ = phase.id

        // Codable
        let data = try? JSONEncoder().encode(phase)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = ManifestationPhase.self
    }

    @Test("Phase round-trip encoding")
    func roundTrip() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let finish = Date(timeIntervalSince1970: 2000)

        var original = ManifestationPhase(name: .gather, startedAt: start)
        original.finishedAt = finish
        original.observation = "Gathered 10 events"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ManifestationPhase.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.id == original.id)
        #expect(decoded.startedAt == original.startedAt)
        #expect(decoded.finishedAt == original.finishedAt)
        #expect(decoded.observation == original.observation)
    }

    @Test("Phase names have correct raw values")
    func phaseNamesCorrect() {
        #expect(ManifestationPhase.PhaseName.gather.rawValue == "gather")
        #expect(ManifestationPhase.PhaseName.mine.rawValue == "mine")
        #expect(ManifestationPhase.PhaseName.propose.rawValue == "propose")
        #expect(ManifestationPhase.PhaseName.consolidate.rawValue == "consolidate")
        #expect(ManifestationPhase.PhaseName.summarize.rawValue == "summarize")
    }
}

// MARK: - ManifestationProposal Tests

@Suite("ManifestationProposal")
struct ManifestationProposalTests {

    @Test("All Kind cases exist")
    func allKindsExist() {
        let kinds: [ManifestationProposal.Kind] = [
            .newSkill, .skillImprovement, .skillMerge, .skillRetire,
            .newMemoryCandidate, .memoryConsolidation, .observation
        ]
        #expect(kinds.count == 7)
    }

    @Test("Proposal initializes correctly")
    func initializesCorrectly() {
        let proposal = ManifestationProposal(
            kind: .newSkill,
            title: "Add git workflow skill",
            rationale: "User frequently uses git commands",
            confidence: 0.85,
            payloadJSON: "{\"name\":\"git_workflow\"}"
        )

        #expect(proposal.kind == .newSkill)
        #expect(proposal.title == "Add git workflow skill")
        #expect(proposal.rationale == "User frequently uses git commands")
        #expect(proposal.confidence == 0.85)
        #expect(proposal.payloadJSON == "{\"name\":\"git_workflow\"}")
        #expect(proposal.id != "")
        #expect(proposal.createdAt <= Date())
    }

    @Test("Proposal initializes with custom date")
    func initializesWithCustomDate() {
        let date = Date(timeIntervalSince1970: 1000)
        let proposal = ManifestationProposal(
            kind: .observation,
            title: "Pattern observed",
            rationale: "Noted recurring pattern",
            confidence: 0.5,
            payloadJSON: "{}",
            createdAt: date
        )

        #expect(proposal.createdAt == date)
    }

    @Test("Proposal confidence is in valid range")
    func confidenceInRange() {
        let high = ManifestationProposal(
            kind: .newSkill,
            title: "High confidence",
            rationale: "Strong pattern",
            confidence: 1.0,
            payloadJSON: "{}"
        )

        let low = ManifestationProposal(
            kind: .observation,
            title: "Low confidence",
            rationale: "Weak pattern",
            confidence: 0.0,
            payloadJSON: "{}"
        )

        #expect(high.confidence == 1.0)
        #expect(low.confidence == 0.0)
    }

    @Test("Proposal is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let proposal = ManifestationProposal(
            kind: .skillMerge,
            title: "Merge skills",
            rationale: "Duplicate detected",
            confidence: 0.7,
            payloadJSON: "{}"
        )

        // Identifiable
        _ = proposal.id

        // Codable
        let data = try? JSONEncoder().encode(proposal)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = ManifestationProposal.self
    }

    @Test("Proposal round-trip encoding")
    func roundTrip() throws {
        let created = Date(timeIntervalSince1970: 1000)
        let original = ManifestationProposal(
            kind: .skillRetire,
            title: "Retire old skill",
            rationale: "Skill no longer needed",
            confidence: 0.9,
            payloadJSON: "{\"skill_id\":\"old_skill\"}",
            createdAt: created
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ManifestationProposal.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.kind == original.kind)
        #expect(decoded.title == original.title)
        #expect(decoded.rationale == original.rationale)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.payloadJSON == original.payloadJSON)
        #expect(decoded.createdAt == original.createdAt)
    }

    @Test("Proposal Kind raw values are correct")
    func kindRawValuesCorrect() {
        #expect(ManifestationProposal.Kind.newSkill.rawValue == "newSkill")
        #expect(ManifestationProposal.Kind.skillImprovement.rawValue == "skillImprovement")
        #expect(ManifestationProposal.Kind.skillMerge.rawValue == "skillMerge")
        #expect(ManifestationProposal.Kind.skillRetire.rawValue == "skillRetire")
        #expect(ManifestationProposal.Kind.newMemoryCandidate.rawValue == "newMemoryCandidate")
        #expect(ManifestationProposal.Kind.memoryConsolidation.rawValue == "memoryConsolidation")
        #expect(ManifestationProposal.Kind.observation.rawValue == "observation")
    }

    @Test("Proposal handles long rationale")
    func handlesLongRationale() {
        let longRationale = String(repeating: "Rationale text. ", count: 1000)
        let proposal = ManifestationProposal(
            kind: .observation,
            title: "Test",
            rationale: longRationale,
            confidence: 0.5,
            payloadJSON: "{}"
        )

        #expect(proposal.rationale.count > 10000)
    }

    @Test("Proposal handles complex JSON payload")
    func handlesComplexPayload() {
        let complexJSON = """
        {
            "name": "test_skill",
            "version": 1,
            "dependencies": ["dep1", "dep2"],
            "config": {"enabled": true, "timeout": 30}
        }
        """
        let proposal = ManifestationProposal(
            kind: .newSkill,
            title: "Complex skill",
            rationale: "Test",
            confidence: 0.8,
            payloadJSON: complexJSON
        )

        #expect(proposal.payloadJSON == complexJSON)
    }
}

// MARK: - Manifestation Tests

@Suite("Manifestation Initialization")
struct ManifestationInitializationTests {

    @Test("Manifestation initializes with trigger reason")
    func initializesWithTriggerReason() {
        let manifestation = Manifestation(triggerReason: "scheduled-daily")

        #expect(manifestation.triggerReason == "scheduled-daily")
        #expect(manifestation.status == .running)
        #expect(manifestation.phases.isEmpty)
        #expect(manifestation.proposals.isEmpty)
        #expect(manifestation.summary == nil)
        #expect(manifestation.finishedAt == nil)
        #expect(manifestation.auditWindowStart == nil)
        #expect(manifestation.auditWindowEnd == nil)
        #expect(manifestation.id != "")
        #expect(manifestation.startedAt <= Date())
    }

    @Test("Manifestation initializes with custom start time")
    func initializesWithCustomStart() {
        let date = Date(timeIntervalSince1970: 1000)
        let manifestation = Manifestation(
            triggerReason: "manual",
            startedAt: date
        )

        #expect(manifestation.triggerReason == "manual")
        #expect(manifestation.startedAt == date)
    }

    @Test("Manifestation is Codable, Sendable, and Identifiable")
    func conformsToProtocols() {
        let manifestation = Manifestation(triggerReason: "test")

        // Identifiable
        _ = manifestation.id

        // Codable
        let data = try? JSONEncoder().encode(manifestation)
        #expect(data != nil)

        // Sendable (compile-time check)
        let _: any Sendable.Type = Manifestation.self
    }

    @Test("Manifestation round-trip encoding")
    func roundTrip() throws {
        let started = Date(timeIntervalSince1970: 1000)
        let finished = Date(timeIntervalSince1970: 2000)

        var original = Manifestation(
            triggerReason: "idle-trigger",
            startedAt: started
        )
        original.status = .completed
        original.finishedAt = finished
        original.summary = "Found 5 patterns"
        original.auditWindowStart = started
        original.auditWindowEnd = finished

        original.phases = [
            ManifestationPhase(name: .gather, startedAt: started)
        ]

        original.proposals = [
            ManifestationProposal(
                kind: .newSkill,
                title: "Test proposal",
                rationale: "Test rationale",
                confidence: 0.8,
                payloadJSON: "{}"
            )
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Manifestation.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.triggerReason == original.triggerReason)
        #expect(decoded.startedAt == original.startedAt)
        #expect(decoded.status == original.status)
        #expect(decoded.finishedAt == original.finishedAt)
        #expect(decoded.summary == original.summary)
        #expect(decoded.auditWindowStart == original.auditWindowStart)
        #expect(decoded.auditWindowEnd == original.auditWindowEnd)
        #expect(decoded.phases.count == original.phases.count)
        #expect(decoded.proposals.count == original.proposals.count)
    }
}

@Suite("Manifestation Lifecycle")
struct ManifestationLifecycleTests {

    @Test("Manifestation transitions from running to completed")
    func runningToCompleted() {
        var manifestation = Manifestation(triggerReason: "test")

        manifestation.status = .completed
        manifestation.finishedAt = Date()
        manifestation.summary = "Done"

        #expect(manifestation.status == .completed)
        #expect(manifestation.finishedAt != nil)
        #expect(manifestation.summary == "Done")
    }

    @Test("Manifestation transitions from running to failed")
    func runningToFailed() {
        var manifestation = Manifestation(triggerReason: "test")

        manifestation.status = .failed
        manifestation.finishedAt = Date()

        #expect(manifestation.status == .failed)
    }

    @Test("Manifestation can be skipped")
    func canBeSkipped() {
        var manifestation = Manifestation(triggerReason: "test")

        manifestation.status = .skipped
        manifestation.finishedAt = Date()
        manifestation.summary = "No new events"

        #expect(manifestation.status == .skipped)
    }

    @Test("Manifestation with phases records progress")
    func recordsProgress() {
        let started = Date()
        var manifestation = Manifestation(triggerReason: "test", startedAt: started)

        var gather = ManifestationPhase(name: .gather, startedAt: started)
        gather.finishedAt = Date()
        gather.observation = "Gathered 10 events"

        var mine = ManifestationPhase(name: .mine)
        mine.finishedAt = Date()
        mine.observation = "Found 3 proposals"

        manifestation.phases = [gather, mine]

        #expect(manifestation.phases.count == 2)
        #expect(manifestation.phases[0].name == .gather)
        #expect(manifestation.phases[1].name == .mine)
    }

    @Test("Manifestation with proposals records findings")
    func recordsFindings() {
        var manifestation = Manifestation(triggerReason: "test")

        manifestation.proposals = [
            ManifestationProposal(
                kind: .newSkill,
                title: "Skill 1",
                rationale: "Rationale 1",
                confidence: 0.9,
                payloadJSON: "{}"
            ),
            ManifestationProposal(
                kind: .observation,
                title: "Observation 1",
                rationale: "Rationale 2",
                confidence: 0.6,
                payloadJSON: "{}"
            )
        ]

        #expect(manifestation.proposals.count == 2)
        #expect(manifestation.proposals[0].kind == .newSkill)
        #expect(manifestation.proposals[1].kind == .observation)
    }

    @Test("Manifestation tracks audit window")
    func tracksAuditWindow() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)

        var manifestation = Manifestation(triggerReason: "test")
        manifestation.auditWindowStart = start
        manifestation.auditWindowEnd = end

        #expect(manifestation.auditWindowStart == start)
        #expect(manifestation.auditWindowEnd == end)
    }
}

@Suite("Manifestation Edge Cases")
struct ManifestationEdgeCaseTests {

    @Test("Manifestation handles empty trigger reason")
    func handlesEmptyTriggerReason() {
        let manifestation = Manifestation(triggerReason: "")
        #expect(manifestation.triggerReason == "")
    }

    @Test("Manifestation handles long trigger reason")
    func handlesLongTriggerReason() {
        let longReason = String(repeating: "Trigger ", count: 100)
        let manifestation = Manifestation(triggerReason: longReason)
        #expect(manifestation.triggerReason.count >= 800)
        #expect(manifestation.triggerReason == longReason)
    }

    @Test("Manifestation handles empty phases")
    func handlesEmptyPhases() {
        let manifestation = Manifestation(triggerReason: "test")
        #expect(manifestation.phases.isEmpty)
    }

    @Test("Manifestation handles many phases")
    func handlesManyPhases() {
        var manifestation = Manifestation(triggerReason: "test")

        for _ in 1...100 {
            let phase = ManifestationPhase(name: .gather)
            manifestation.phases.append(phase)
        }

        #expect(manifestation.phases.count == 100)
    }

    @Test("Manifestation handles empty proposals")
    func handlesEmptyProposals() {
        let manifestation = Manifestation(triggerReason: "test")
        #expect(manifestation.proposals.isEmpty)
    }

    @Test("Manifestation handles many proposals")
    func handlesManyProposals() {
        var manifestation = Manifestation(triggerReason: "test")

        for i in 1...50 {
            let proposal = ManifestationProposal(
                kind: .observation,
                title: "Proposal \(i)",
                rationale: "Rationale \(i)",
                confidence: Double(i) / 100.0,
                payloadJSON: "{}"
            )
            manifestation.proposals.append(proposal)
        }

        #expect(manifestation.proposals.count == 50)
    }

    @Test("Manifestation handles long summary")
    func handlesLongSummary() {
        var manifestation = Manifestation(triggerReason: "test")
        manifestation.summary = String(repeating: "Summary text. ", count: 1000)

        #expect(manifestation.summary?.count ?? 0 > 10000)
    }

    @Test("Manifestation timestamps are consistent")
    func timestampsConsistent() {
        let before = Date()
        let manifestation = Manifestation(triggerReason: "test")
        let after = Date()

        #expect(manifestation.startedAt >= before)
        #expect(manifestation.startedAt <= after)
    }
}

@Suite("Manifestation JSON Serialization")
struct ManifestationJSONTests {

    @Test("Serializes to valid JSON")
    func serializesToJSON() throws {
        let manifestation = Manifestation(triggerReason: "test-json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifestation)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        #expect(json?["triggerReason"] as? String == "test-json")
        #expect(json?["status"] as? String == "running")
    }

    @Test("Deserializes from JSON")
    func deserializesFromJSON() throws {
        let json = """
        {
            "id": "manifest-123",
            "startedAt": "2024-01-01T00:00:00Z",
            "finishedAt": "2024-01-01T00:01:00Z",
            "status": "completed",
            "phases": [
                {
                    "id": "phase-1",
                    "name": "gather",
                    "startedAt": "2024-01-01T00:00:00Z",
                    "finishedAt": "2024-01-01T00:00:10Z",
                    "observation": "Gathered 5 events"
                }
            ],
            "proposals": [
                {
                    "id": "proposal-1",
                    "kind": "observation",
                    "title": "Test observation",
                    "rationale": "Test rationale",
                    "confidence": 0.75,
                    "payloadJSON": "{}",
                    "createdAt": "2024-01-01T00:00:30Z"
                }
            ],
            "summary": "Found 1 pattern",
            "triggerReason": "manual",
            "auditWindowStart": "2024-01-01T00:00:00Z",
            "auditWindowEnd": "2024-01-01T00:00:45Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifestation = try decoder.decode(Manifestation.self, from: json.data(using: .utf8)!)

        #expect(manifestation.id == "manifest-123")
        #expect(manifestation.status == .completed)
        #expect(manifestation.triggerReason == "manual")
        #expect(manifestation.summary == "Found 1 pattern")
        #expect(manifestation.phases.count == 1)
        #expect(manifestation.proposals.count == 1)
        #expect(manifestation.proposals[0].confidence == 0.75)
    }
}
