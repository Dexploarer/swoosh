// Tests/SwooshAPITests/SkillMemoryRoutesTests.swift — Tier 1
//
// Wire-level coverage for /api/skills/* CRUD and /api/memories/* CRUD.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

private func sampleSkillSummary(
    id: String = "s1",
    trust: String = "draft"
) -> SkillSummary {
    SkillSummary(
        id: id,
        title: "Ship the API",
        description: "Use the API",
        category: "coding",
        trust: trust
    )
}

private func sampleMemorySummary(
    id: String = "m1",
    status: String = "approved"
) -> MemorySummary {
    MemorySummary(
        id: id,
        text: "User likes dark mode",
        category: "preference",
        status: status,
        sensitivity: "low",
        confidence: 0.9,
        createdAt: "2026-05-22T00:00:00Z"
    )
}

@Suite("Skill CRUD routes")
struct SkillCRUDRoutesTests {

    @Test("GET /api/skills/:id returns detail")
    func skillDetail() async throws {
        let sources = SwooshAPIRuntimeSources(
            skillDetail: { id in
                SkillDetailResponse(
                    skill: sampleSkillSummary(id: id),
                    body: "Run `swift build`.",
                    tags: ["build", "ci"],
                    triggerPatterns: ["build the app"],
                    toolsRequired: ["bash"],
                    platforms: ["macOS"],
                    usageCount: 3,
                    successRate: 0.66,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/skills/abc", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try crudTestDecoder().decode(SkillDetailResponse.self, from: Data(buffer: response.body))
                #expect(body.skill.id == "abc")
                #expect(body.body.contains("swift build"))
            }
        }
    }

    @Test("POST /api/skills/search invokes searchSkills")
    func searchSkills() async throws {
        let received = SkillSearchBox()
        let sources = SwooshAPIRuntimeSources(
            searchSkills: { request in
                await received.set(request)
                return SkillsResponse(skills: [sampleSkillSummary(id: "match")])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(SkillSearchRequest(query: "build", limit: 5))
            try await client.execute(
                uri: "/api/skills/search", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(SkillsResponse.self, from: Data(buffer: response.body))
                #expect(decoded.skills.first?.id == "match")
            }
        }
        #expect(await received.value?.query == "build")
        #expect(await received.value?.limit == 5)
    }

    @Test("POST /api/skills creates a draft skill")
    func proposeSkill() async throws {
        let received = SkillProposeBox()
        let sources = SwooshAPIRuntimeSources(
            proposeSkill: { request in
                await received.set(request)
                return SkillMutationResponse(
                    skill: sampleSkillSummary(id: "new"),
                    message: "Skill draft created."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(SkillProposeRequest(
                title: "Test skill",
                description: "Test",
                body: "Run something."
            ))
            try await client.execute(
                uri: "/api/skills", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(SkillMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.skill.id == "new")
            }
        }
        #expect(await received.value?.title == "Test skill")
    }

    @Test("POST /api/skills/:id/approve promotes the skill")
    func approveSkill() async throws {
        let captured = SkillIDBox()
        let sources = SwooshAPIRuntimeSources(
            approveSkill: { id in
                await captured.set(id)
                return SkillMutationResponse(
                    skill: sampleSkillSummary(id: id, trust: "reviewed"),
                    message: "Skill approved."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/skills/abc/approve", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(SkillMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.skill.trust == "reviewed")
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("POST /api/skills/:id/reject sets the skill to rejected")
    func rejectSkill() async throws {
        let captured = SkillIDBox()
        let sources = SwooshAPIRuntimeSources(
            rejectSkill: { id in
                await captured.set(id)
                return SkillMutationResponse(
                    skill: sampleSkillSummary(id: id, trust: "rejected"),
                    message: "Skill rejected."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/skills/abc/reject", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(SkillMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.skill.trust == "rejected")
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("DELETE /api/skills/:id maps to deleteSkill")
    func deleteSkill() async throws {
        let captured = SkillIDBox()
        let sources = SwooshAPIRuntimeSources(
            deleteSkill: { id in
                await captured.set(id)
                return SkillsResponse(skills: [])
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/skills/abc", method: .delete,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try crudTestDecoder().decode(SkillsResponse.self, from: Data(buffer: response.body))
                #expect(body.skills.isEmpty)
            }
        }
        #expect(await captured.value == "abc")
    }
}

@Suite("Memory CRUD routes")
struct MemoryCRUDRoutesTests {

    @Test("GET /api/memories/:id returns detail")
    func memoryDetail() async throws {
        let sources = SwooshAPIRuntimeSources(
            memoryDetail: { id in
                MemoryDetailResponse(
                    memory: sampleMemorySummary(id: id),
                    evidenceJSON: "{\"source\":\"scout\"}"
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/memories/abc", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let body = try crudTestDecoder().decode(MemoryDetailResponse.self, from: Data(buffer: response.body))
                #expect(body.memory.id == "abc")
                #expect(body.evidenceJSON == "{\"source\":\"scout\"}")
            }
        }
    }

    @Test("POST /api/memories proposes a candidate")
    func proposeMemory() async throws {
        let received = MemoryProposeBox()
        let sources = SwooshAPIRuntimeSources(
            proposeMemory: { request in
                await received.set(request)
                return MemoryMutationResponse(
                    memory: sampleMemorySummary(id: "new", status: "pending"),
                    message: "Memory candidate proposed."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(MemoryProposeRequest(
                text: "User likes dark mode",
                category: "preference"
            ))
            try await client.execute(
                uri: "/api/memories", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(MemoryMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.memory.status == "pending")
            }
        }
        #expect(await received.value?.text == "User likes dark mode")
    }

    @Test("POST /api/memories/:id/approve promotes to approved")
    func approveMemory() async throws {
        let captured = MemoryIDBox()
        let sources = SwooshAPIRuntimeSources(
            approveMemory: { id in
                await captured.set(id)
                return MemoryMutationResponse(
                    memory: sampleMemorySummary(id: id, status: "approved"),
                    message: "Memory approved."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/memories/abc/approve", method: .post,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(MemoryMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.memory.status == "approved")
            }
        }
        #expect(await captured.value == "abc")
    }

    @Test("POST /api/memories/:id/reject passes reason")
    func rejectMemory() async throws {
        let receivedID = MemoryIDBox()
        let receivedBody = MemoryReviewBox()
        let sources = SwooshAPIRuntimeSources(
            rejectMemory: { id, body in
                await receivedID.set(id)
                await receivedBody.set(body)
                return MemoryMutationResponse(
                    memory: sampleMemorySummary(id: id, status: "rejected"),
                    message: "Memory rejected."
                )
            }
        )
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources).build()
        try await app.test(.router) { client in
            let body = try JSONEncoder().encode(MemoryReviewRequest(reason: "Stale"))
            try await client.execute(
                uri: "/api/memories/abc/reject", method: .post,
                headers: [.authorization: "Bearer secret", .contentType: "application/json"],
                body: .init(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let decoded = try crudTestDecoder().decode(MemoryMutationResponse.self, from: Data(buffer: response.body))
                #expect(decoded.memory.status == "rejected")
            }
        }
        #expect(await receivedID.value == "abc")
        #expect(await receivedBody.value?.reason == "Stale")
    }
}

private actor SkillIDBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor SkillSearchBox {
    private var stored: SkillSearchRequest?
    func set(_ value: SkillSearchRequest) { stored = value }
    var value: SkillSearchRequest? { stored }
}

private actor SkillProposeBox {
    private var stored: SkillProposeRequest?
    func set(_ value: SkillProposeRequest) { stored = value }
    var value: SkillProposeRequest? { stored }
}

private actor MemoryIDBox {
    private var stored: String?
    func set(_ value: String) { stored = value }
    var value: String? { stored }
}

private actor MemoryProposeBox {
    private var stored: MemoryProposeRequest?
    func set(_ value: MemoryProposeRequest) { stored = value }
    var value: MemoryProposeRequest? { stored }
}

private actor MemoryReviewBox {
    private var stored: MemoryReviewRequest?
    func set(_ value: MemoryReviewRequest) { stored = value }
    var value: MemoryReviewRequest? { stored }
}

private func crudTestDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
