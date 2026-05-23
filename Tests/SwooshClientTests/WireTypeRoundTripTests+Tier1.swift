// Tests/SwooshClientTests/WireTypeRoundTripTests+Tier1.swift — 0.4A
//
// Round-trip Codable tests for the tier-1 wire types added in the recent
// API push (goals, manifestations, skills CRUD, memories CRUD, tool
// execution). The audit flagged these as having no client-side decode
// coverage — a server-side rename would silently break the iPhone
// without these tests.

import Foundation
import Testing
@testable import SwooshClient

@Suite("Wire type round trips — Tier 1 (records, skills, memories, tools)")
struct WireTypeRoundTripTier1Tests {

    private let encoder = JSONEncoder.swooshDefault
    private let decoder = JSONDecoder.swooshDefault

    // MARK: - Goals

    @Test("GoalSetRequest round-trips")
    func goalSetRequest() throws {
        let value = GoalSetRequest(statement: "Ship the audit fix", maxIterations: 8, parentSessionID: "s1")
        let decoded = try decoder.decode(GoalSetRequest.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("GoalUpdateRequest round-trips")
    func goalUpdateRequest() throws {
        let value = GoalUpdateRequest(state: "paused")
        let decoded = try decoder.decode(GoalUpdateRequest.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("GoalDetailResponse round-trips with iterations")
    func goalDetailResponse() throws {
        let goal = GoalRecordSummary(
            id: "g-1",
            statement: "ship",
            state: "active",
            progress: "in flight",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let value = GoalDetailResponse(
            goal: goal,
            maxIterations: 6,
            parentSessionID: "s1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            iterations: [
                GoalIterationSummary(
                    id: "i-1",
                    iteration: 1,
                    sessionID: "s1",
                    observation: "no progress yet",
                    judgement: "continue",
                    judgeRationale: nil,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100)
                ),
            ]
        )
        let decoded = try decoder.decode(GoalDetailResponse.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("GoalsResponse + GoalMutationResponse round-trip")
    func goalListAndMutation() throws {
        let goal = GoalRecordSummary(
            id: "g-1",
            statement: "ship",
            state: "active",
            progress: "in flight",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let list = GoalsResponse(goals: [goal])
        let mutation = GoalMutationResponse(goal: goal, message: "ok")
        #expect(try decoder.decode(GoalsResponse.self, from: try encoder.encode(list)) == list)
        #expect(try decoder.decode(GoalMutationResponse.self, from: try encoder.encode(mutation)) == mutation)
    }

    // MARK: - Manifestations

    @Test("ManifestationDetailResponse round-trips with phases and proposals")
    func manifestationDetail() throws {
        let summary = ManifestationRecordSummary(
            id: "m-1",
            status: "completed",
            triggerReason: "idle",
            proposalCount: 1,
            summary: "Mined one skill",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let value = ManifestationDetailResponse(
            manifestation: summary,
            phases: [
                ManifestationPhaseSummary(
                    id: "p-1",
                    name: "gather",
                    startedAt: Date(timeIntervalSince1970: 1_800_000_010),
                    finishedAt: Date(timeIntervalSince1970: 1_800_000_020),
                    observation: nil
                ),
            ],
            proposals: [
                ManifestationProposalSummary(
                    id: "pp-1",
                    kind: "skill",
                    title: "audit module",
                    rationale: "repeated 3 times",
                    confidence: 0.8,
                    payloadJSON: "{}",
                    createdAt: Date(timeIntervalSince1970: 1_800_000_030)
                ),
            ],
            auditWindowStart: Date(timeIntervalSince1970: 1_799_900_000),
            auditWindowEnd: Date(timeIntervalSince1970: 1_800_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_800_000_050)
        )
        let decoded = try decoder.decode(ManifestationDetailResponse.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("ManifestationRunRequest round-trips a nil triggerReason")
    func manifestationRunRequest() throws {
        let value = ManifestationRunRequest()
        let decoded = try decoder.decode(ManifestationRunRequest.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    // MARK: - Skills CRUD

    @Test("SkillDetailResponse round-trips")
    func skillDetail() throws {
        let skill = SkillSummary(
            id: "bundled.review",
            title: "Review",
            description: "Review a branch.",
            category: "coding",
            trust: "promoted"
        )
        let value = SkillDetailResponse(
            skill: skill,
            body: "# Review",
            tags: ["coding"],
            triggerPatterns: ["review the branch"],
            toolsRequired: ["git.status"],
            platforms: ["macOS"],
            usageCount: 4,
            successRate: 0.75,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let decoded = try decoder.decode(SkillDetailResponse.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("SkillSearchRequest + SkillProposeRequest + SkillMutationResponse round-trip")
    func skillRequestsAndMutation() throws {
        let search = SkillSearchRequest(query: "audit", limit: 5)
        let propose = SkillProposeRequest(
            title: "Audit module",
            description: "Audit a Sources/* directory.",
            body: "# Audit",
            category: "process",
            tags: ["coding"],
            triggerPatterns: ["audit"]
        )
        let skill = SkillSummary(id: "p-1", title: "X", description: "Y", category: "z", trust: "draft")
        let mutation = SkillMutationResponse(skill: skill, message: "queued for review")
        #expect(try decoder.decode(SkillSearchRequest.self, from: try encoder.encode(search)) == search)
        #expect(try decoder.decode(SkillProposeRequest.self, from: try encoder.encode(propose)) == propose)
        #expect(try decoder.decode(SkillMutationResponse.self, from: try encoder.encode(mutation)) == mutation)
    }

    // MARK: - Memories CRUD

    @Test("MemoryDetailResponse round-trips with evidence JSON")
    func memoryDetail() throws {
        let summary = MemorySummary(
            id: "mem-1",
            text: "User prefers Detour persona",
            category: "preferences",
            status: "approved",
            sensitivity: "low",
            confidence: 0.9,
            createdAt: "2026-05-22T03:00:00Z"
        )
        let value = MemoryDetailResponse(memory: summary, evidenceJSON: "{\"src\":\"chat\"}")
        let decoded = try decoder.decode(MemoryDetailResponse.self, from: try encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("MemoryProposeRequest + MemoryReviewRequest + MemoryMutationResponse round-trip")
    func memoryRequestsAndMutation() throws {
        let propose = MemoryProposeRequest(
            text: "User uses Detour, not Swoosh",
            category: "preferences",
            sensitivity: "low",
            confidence: 0.92,
            evidenceJSON: nil
        )
        let review = MemoryReviewRequest(reason: "duplicate")
        let mut = MemoryMutationResponse(
            memory: MemorySummary(
                id: "m1",
                text: "x",
                category: "y",
                status: "approved",
                sensitivity: "low",
                confidence: nil,
                createdAt: "2026-01-01T00:00:00Z"
            ),
            message: "approved"
        )
        #expect(try decoder.decode(MemoryProposeRequest.self, from: try encoder.encode(propose)) == propose)
        #expect(try decoder.decode(MemoryReviewRequest.self, from: try encoder.encode(review)) == review)
        #expect(try decoder.decode(MemoryMutationResponse.self, from: try encoder.encode(mut)) == mut)
    }

    // MARK: - Tool execution

    @Test("ToolExecuteRequest + Response round-trip")
    func toolExecute() throws {
        let req = ToolExecuteRequest(argsJSON: "{\"query\":\"hello\"}", sessionID: "s1")
        let resp = ToolExecuteResponse(
            toolName: "memory.search",
            success: true,
            outputJSON: "{\"hits\":0}",
            error: nil,
            durationMs: 12
        )
        #expect(try decoder.decode(ToolExecuteRequest.self, from: try encoder.encode(req)) == req)
        #expect(try decoder.decode(ToolExecuteResponse.self, from: try encoder.encode(resp)) == resp)
    }
}
