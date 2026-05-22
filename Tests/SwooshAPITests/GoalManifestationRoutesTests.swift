// Tests/SwooshAPITests/GoalManifestationRoutesTests.swift — Tier 1
//
// Wire-level coverage for /api/goals/* and /api/manifestations/*.
// Same shape as PluginRoutesTests — runtime callbacks return canned
// payloads; the assertions verify the router hooks them up and
// serializes the typed wire shapes correctly.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

private func sampleGoal(
    id: String = "g1",
    state: String = "active",
    progress: String = "1/20"
) -> GoalRecordSummary {
    GoalRecordSummary(
        id: id,
        statement: "Ship the API",
        state: state,
        progress: progress,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func sampleManifestation(
    id: String = "m1",
    status: String = "completed"
) -> ManifestationRecordSummary {
    ManifestationRecordSummary(
        id: id,
        status: status,
        triggerReason: "manual",
        proposalCount: 2,
        summary: "Found 2 things",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Suite("Goal routes")
struct GoalRoutesTests {

    @Test("GET /api/goals returns the runtime-source list")
    func listGoals() async throws {
        let sources = SwooshAPIRuntimeSources(
            goals: {
                GoalsResponse(goals: [sampleGoal(id: "a"), sampleGoal(id: "b")])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/goals", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try goalsTestDecoder().decode(GoalsResponse.self, from: Data(buffer: response.body))
                #expect(body.goals.map(\.id) == ["a", "b"])
            }
        }
    }

    @Test("GET /api/goals/:id returns detail")
    func goalDetail() async throws {
        let sources = SwooshAPIRuntimeSources(
            goalDetail: { id in
                GoalDetailResponse(
                    goal: sampleGoal(id: id),
                    maxIterations: 20,
                    parentSessionID: "session-1",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    iterations: [
                        GoalIterationSummary(
                            id: "iter-1",
                            iteration: 1,
                            sessionID: "session-1",
                            observation: "Made progress",
                            judgement: "progressing",
                            judgeRationale: nil,
                            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
                        )
                    ]
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/goals/abc", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try goalsTestDecoder().decode(GoalDetailResponse.self, from: Data(buffer: response.body))
                #expect(body.goal.id == "abc")
                #expect(body.iterations.count == 1)
                #expect(body.iterations.first?.judgement == "progressing")
            }
        }
    }

    @Test("POST /api/goals invokes setGoal source")
    func setGoal() async throws {
        let received = GoalRequestBox()
        let sources = SwooshAPIRuntimeSources(
            setGoal: { request in
                await received.set(request)
                return GoalMutationResponse(
                    goal: sampleGoal(id: "new"),
                    message: "Goal created."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(GoalSetRequest(statement: "Ship it"))
            try await client.execute(
                uri: "/api/goals", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try goalsTestDecoder().decode(GoalMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.goal.id == "new")
            }
        }
        #expect(await received.value?.statement == "Ship it")
    }

    @Test("POST /api/goals/:id/abandon maps id to abandonGoal")
    func abandonGoal() async throws {
        let captured = GoalIDBox()
        let sources = SwooshAPIRuntimeSources(
            abandonGoal: { id in
                await captured.set(id)
                return GoalMutationResponse(
                    goal: sampleGoal(id: id, state: "abandoned", progress: "0/20"),
                    message: "Goal abandoned."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/goals/abc/abandon", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try goalsTestDecoder().decode(GoalMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.goal.state == "abandoned")
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("PATCH /api/goals/:id maps id+body to updateGoal")
    func updateGoal() async throws {
        let receivedID = GoalIDBox()
        let receivedBody = GoalUpdateBox()
        let sources = SwooshAPIRuntimeSources(
            updateGoal: { id, body in
                await receivedID.set(id)
                await receivedBody.set(body)
                return GoalMutationResponse(
                    goal: sampleGoal(id: id, state: body.state),
                    message: "Goal updated."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(GoalUpdateRequest(state: "paused"))
            try await client.execute(
                uri: "/api/goals/abc", method: .patch,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try goalsTestDecoder().decode(GoalMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.goal.state == "paused")
            }
        }
        #expect(await receivedID.value == "abc")
        #expect(await receivedBody.value?.state == "paused")
    }
}

@Suite("Manifestation routes")
struct ManifestationRoutesTests {

    @Test("GET /api/manifestations returns the source list")
    func listManifestations() async throws {
        let sources = SwooshAPIRuntimeSources(
            manifestations: {
                ManifestationsResponse(manifestations: [sampleManifestation(id: "x"), sampleManifestation(id: "y")])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/manifestations", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try goalsTestDecoder().decode(ManifestationsResponse.self, from: Data(buffer: response.body))
                #expect(body.manifestations.map(\.id) == ["x", "y"])
            }
        }
    }

    @Test("GET /api/manifestations/:id returns detail")
    func manifestationDetail() async throws {
        let sources = SwooshAPIRuntimeSources(
            manifestationDetail: { id in
                ManifestationDetailResponse(
                    manifestation: sampleManifestation(id: id),
                    phases: [
                        ManifestationPhaseSummary(
                            id: "p1",
                            name: "gather",
                            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                            finishedAt: Date(timeIntervalSince1970: 1_700_000_010),
                            observation: "Pulled events"
                        )
                    ],
                    proposals: [
                        ManifestationProposalSummary(
                            id: "prop1",
                            kind: "newSkill",
                            title: "Suggest skill",
                            rationale: "User did X a lot",
                            confidence: 0.7,
                            payloadJSON: "{}",
                            createdAt: Date(timeIntervalSince1970: 1_700_000_010)
                        )
                    ],
                    auditWindowStart: Date(timeIntervalSince1970: 1_700_000_000),
                    auditWindowEnd: Date(timeIntervalSince1970: 1_700_000_010),
                    finishedAt: Date(timeIntervalSince1970: 1_700_000_020)
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/manifestations/m42", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try goalsTestDecoder().decode(ManifestationDetailResponse.self, from: Data(buffer: response.body))
                #expect(body.manifestation.id == "m42")
                #expect(body.proposals.count == 1)
                #expect(body.phases.first?.name == "gather")
            }
        }
    }

    @Test("POST /api/manifestations/run invokes runManifestation")
    func runManifestation() async throws {
        let received = ManifestationRunBox()
        let sources = SwooshAPIRuntimeSources(
            runManifestation: { request in
                await received.set(request)
                return ManifestationDetailResponse(
                    manifestation: sampleManifestation(id: "fresh", status: "running"),
                    phases: [],
                    proposals: [],
                    auditWindowStart: nil,
                    auditWindowEnd: nil,
                    finishedAt: nil
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(ManifestationRunRequest(triggerReason: "test"))
            try await client.execute(
                uri: "/api/manifestations/run", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try goalsTestDecoder().decode(ManifestationDetailResponse.self, from: Data(buffer: response.body))
                #expect(decoded.manifestation.id == "fresh")
            }
        }
        #expect(await received.value?.triggerReason == "test")
    }

    @Test("DELETE /api/manifestations/:id maps to deleteManifestation")
    func deleteManifestation() async throws {
        let captured = GoalIDBox()
        let sources = SwooshAPIRuntimeSources(
            deleteManifestation: { id in
                await captured.set(id)
                return ManifestationsResponse(manifestations: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/manifestations/m1", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try goalsTestDecoder().decode(ManifestationsResponse.self, from: Data(buffer: response.body))
                #expect(body.manifestations.isEmpty)
            }
        }
        #expect(await captured.value == "m1")
    }
}

private actor GoalIDBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor GoalRequestBox {
    private var stored: GoalSetRequest?
    func set(_ value: GoalSetRequest) { stored = value }
    var value: GoalSetRequest? { stored }
}

private actor GoalUpdateBox {
    private var stored: GoalUpdateRequest?
    func set(_ value: GoalUpdateRequest) { stored = value }
    var value: GoalUpdateRequest? { stored }
}

private actor ManifestationRunBox {
    private var stored: ManifestationRunRequest?
    func set(_ value: ManifestationRunRequest) { stored = value }
    var value: ManifestationRunRequest? { stored }
}

private func goalsTestDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
