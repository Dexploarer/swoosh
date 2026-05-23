// Tests/SwooshClientTests/SwooshAPIClientCRUDTests.swift — 0.4A
//
// Coverage for the tier-1 CRUD methods that the audit flagged as
// "exists but has no client-side test" — goals, manifestations, skills,
// memories, and the tool-execute endpoint. Each test pins the HTTP
// method, path encoding, and request/response shape. Server-side
// renames in any of these endpoints will trip an assertion here.

import Foundation
import Testing
@testable import SwooshClient

@Suite("SwooshAPIClient — CRUD endpoints")
struct SwooshAPIClientCRUDTests {

    private func baseURL() -> URL { URL(string: "http://127.0.0.1:8787/")! }

    private func makeClient(token: String = "pair-token") -> SwooshAPIClient {
        SwooshAPIClient(baseURL: baseURL(), token: token, session: MockURLProtocol.makeSession())
    }

    // MARK: - Goals

    @Test("goal(id:) GETs the encoded path and decodes detail")
    func goalDetail() async throws {
        let goal = GoalRecordSummary(
            id: "g/1 raw",
            statement: "ship",
            state: "active",
            progress: "ok",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let body = try JSONEncoder.swooshDefault.encode(GoalDetailResponse(
            goal: goal,
            maxIterations: 4,
            parentSessionID: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            iterations: []
        ))
        try await MockURLProtocol.with({ request in
            // `URL.path` percent-decodes, so check the encoded form via
            // absoluteString — the slash and space in the id must be
            // percent-encoded on the wire.
            #expect(request.url?.absoluteString.hasSuffix("/api/goals/g%2F1%20raw") == true)
            #expect(request.httpMethod == "GET")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let decoded = try await makeClient().goal(id: "g/1 raw")
            #expect(decoded.goal == goal)
        }
    }

    @Test("setGoal posts a GoalSetRequest and returns the mutation")
    func setGoal() async throws {
        let goal = GoalRecordSummary(
            id: "g-1", statement: "ship", state: "active",
            progress: "ok", updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let body = try JSONEncoder.swooshDefault.encode(GoalMutationResponse(goal: goal, message: "created"))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/goals")
            #expect(request.httpMethod == "POST")
            let payload = try! JSONDecoder.swooshDefault.decode(GoalSetRequest.self, from: request.bodyData())
            #expect(payload.statement == "ship")
            #expect(payload.maxIterations == 4)
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let response = try await makeClient().setGoal(.init(statement: "ship", maxIterations: 4))
            #expect(response.message == "created")
        }
    }

    @Test("abandonGoal POSTs the /abandon endpoint")
    func abandonGoal() async throws {
        let goal = GoalRecordSummary(
            id: "g-1", statement: "x", state: "abandoned",
            progress: "ok", updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let body = try JSONEncoder.swooshDefault.encode(GoalMutationResponse(goal: goal, message: "abandoned"))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/goals/g-1/abandon")
            #expect(request.httpMethod == "POST")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let response = try await makeClient().abandonGoal(id: "g-1")
            #expect(response.message == "abandoned")
        }
    }

    @Test("updateGoal PATCHes the goal state")
    func updateGoal() async throws {
        let goal = GoalRecordSummary(
            id: "g-1", statement: "x", state: "paused",
            progress: "ok", updatedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let body = try JSONEncoder.swooshDefault.encode(GoalMutationResponse(goal: goal, message: "paused"))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/goals/g-1")
            #expect(request.httpMethod == "PATCH")
            let payload = try! JSONDecoder.swooshDefault.decode(GoalUpdateRequest.self, from: request.bodyData())
            #expect(payload.state == "paused")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let response = try await makeClient().updateGoal(id: "g-1", body: .init(state: "paused"))
            #expect(response.goal.state == "paused")
        }
    }

    // MARK: - Manifestations

    @Test("manifestation(id:) GETs detail")
    func manifestationDetail() async throws {
        let summary = ManifestationRecordSummary(
            id: "m-1", status: "completed", triggerReason: "idle",
            proposalCount: 0, summary: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let body = try JSONEncoder.swooshDefault.encode(ManifestationDetailResponse(
            manifestation: summary, phases: [], proposals: [],
            auditWindowStart: nil, auditWindowEnd: nil, finishedAt: nil
        ))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/manifestations/m-1")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let decoded = try await makeClient().manifestation(id: "m-1")
            #expect(decoded.manifestation.id == "m-1")
        }
    }

    @Test("runManifestation POSTs the trigger request")
    func runManifestation() async throws {
        let summary = ManifestationRecordSummary(
            id: "m-2", status: "running", triggerReason: "manual",
            proposalCount: 0, summary: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let body = try JSONEncoder.swooshDefault.encode(ManifestationDetailResponse(
            manifestation: summary, phases: [], proposals: [],
            auditWindowStart: nil, auditWindowEnd: nil, finishedAt: nil
        ))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/manifestations/run")
            #expect(request.httpMethod == "POST")
            let payload = try! JSONDecoder.swooshDefault.decode(ManifestationRunRequest.self, from: request.bodyData())
            #expect(payload.triggerReason == "manual")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            _ = try await makeClient().runManifestation(.init(triggerReason: "manual"))
        }
    }

    // MARK: - Skills CRUD

    @Test("skill(id:) GETs the detail body")
    func skillDetail() async throws {
        let skill = SkillSummary(id: "bundled.review", title: "Review", description: "Review", category: "coding", trust: "promoted")
        let body = try JSONEncoder.swooshDefault.encode(SkillDetailResponse(
            skill: skill, body: "# Body", tags: [], triggerPatterns: [],
            toolsRequired: [], platforms: [], usageCount: 0, successRate: 0,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/skills/bundled.review")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let decoded = try await makeClient().skill(id: "bundled.review")
            #expect(decoded.skill.id == "bundled.review")
            #expect(decoded.body == "# Body")
        }
    }

    @Test("searchSkills POSTs a query and decodes the list")
    func searchSkills() async throws {
        let body = try JSONEncoder.swooshDefault.encode(SkillsResponse(skills: [
            SkillSummary(id: "s-1", title: "Audit", description: "", category: "coding", trust: "draft"),
        ]))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/skills/search")
            #expect(request.httpMethod == "POST")
            let payload = try! JSONDecoder.swooshDefault.decode(SkillSearchRequest.self, from: request.bodyData())
            #expect(payload.query == "audit")
            #expect(payload.limit == 5)
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let response = try await makeClient().searchSkills(.init(query: "audit", limit: 5))
            #expect(response.skills.first?.id == "s-1")
        }
    }

    @Test("proposeSkill / approveSkill / rejectSkill / deleteSkill route correctly")
    func skillMutations() async throws {
        let skill = SkillSummary(id: "p-1", title: "X", description: "Y", category: "z", trust: "draft")
        let mut = try JSONEncoder.swooshDefault.encode(SkillMutationResponse(skill: skill, message: "ok"))
        let list = try JSONEncoder.swooshDefault.encode(SkillsResponse(skills: []))

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/skills"):
                let payload = try! JSONDecoder.swooshDefault.decode(SkillProposeRequest.self, from: request.bodyData())
                #expect(payload.title == "Audit")
                return (200, ["Content-Type": "application/json"], mut)
            case ("POST", "/api/skills/p-1/approve"):
                return (200, ["Content-Type": "application/json"], mut)
            case ("POST", "/api/skills/p-1/reject"):
                return (200, ["Content-Type": "application/json"], mut)
            case ("DELETE", "/api/skills/p-1"):
                return (200, ["Content-Type": "application/json"], list)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.proposeSkill(.init(title: "Audit", description: "x", body: "y"))
            _ = try await client.approveSkill(id: "p-1")
            _ = try await client.rejectSkill(id: "p-1")
            _ = try await client.deleteSkill(id: "p-1")
        }
    }

    // MARK: - Memories CRUD

    @Test("memory(id:) GETs detail with evidence")
    func memoryDetail() async throws {
        let summary = MemorySummary(
            id: "mem-1", text: "x", category: "y", status: "approved",
            sensitivity: "low", confidence: 0.8, createdAt: "2026-05-23T03:00:00Z"
        )
        let body = try JSONEncoder.swooshDefault.encode(MemoryDetailResponse(memory: summary, evidenceJSON: "{}"))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/memories/mem-1")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let decoded = try await makeClient().memory(id: "mem-1")
            #expect(decoded.evidenceJSON == "{}")
        }
    }

    @Test("proposeMemory / approveMemory / rejectMemory route correctly")
    func memoryMutations() async throws {
        let summary = MemorySummary(
            id: "mem-1", text: "x", category: "y", status: "approved",
            sensitivity: "low", confidence: nil, createdAt: "2026-05-23T03:00:00Z"
        )
        let mut = try JSONEncoder.swooshDefault.encode(MemoryMutationResponse(memory: summary, message: "ok"))

        try await MockURLProtocol.with({ request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/memories"):
                let payload = try! JSONDecoder.swooshDefault.decode(MemoryProposeRequest.self, from: request.bodyData())
                #expect(payload.text == "x")
                return (200, ["Content-Type": "application/json"], mut)
            case ("POST", "/api/memories/mem-1/approve"):
                return (200, ["Content-Type": "application/json"], mut)
            case ("POST", "/api/memories/mem-1/reject"):
                let payload = try! JSONDecoder.swooshDefault.decode(MemoryReviewRequest.self, from: request.bodyData())
                #expect(payload.reason == "duplicate")
                return (200, ["Content-Type": "application/json"], mut)
            default:
                Issue.record("unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
                return (500, [:], Data())
            }
        }) {
            let client = makeClient()
            _ = try await client.proposeMemory(.init(text: "x", category: "y"))
            _ = try await client.approveMemory(id: "mem-1")
            _ = try await client.rejectMemory(id: "mem-1", body: .init(reason: "duplicate"))
        }
    }

    // MARK: - Tool execution

    @Test("executeTool encodes args and decodes the output")
    func executeTool() async throws {
        let body = try JSONEncoder.swooshDefault.encode(ToolExecuteResponse(
            toolName: "memory.search",
            success: true,
            outputJSON: "{\"hits\":0}",
            error: nil,
            durationMs: 12
        ))
        try await MockURLProtocol.with({ request in
            #expect(request.url?.path == "/api/tools/memory.search/execute")
            #expect(request.httpMethod == "POST")
            let payload = try! JSONDecoder.swooshDefault.decode(ToolExecuteRequest.self, from: request.bodyData())
            #expect(payload.argsJSON == "{\"q\":\"hello\"}")
            #expect(payload.sessionID == "s1")
            return (200, ["Content-Type": "application/json"], body)
        }) {
            let response = try await makeClient().executeTool(
                name: "memory.search",
                body: .init(argsJSON: "{\"q\":\"hello\"}", sessionID: "s1")
            )
            #expect(response.success)
            #expect(response.outputJSON == "{\"hits\":0}")
        }
    }
}
