import HummingbirdTesting
import HTTPTypes
import Testing
@testable import SwooshAPI
import SwooshClient

@Suite("Swoosh API routes")
struct SwooshServerTests {
    @Test("Runtime surfaces return typed state")
    func runtimeSurfacesReturnState() async throws {
        let snapshot = SwooshAPISnapshot(
            providers: [
                ProviderSummary(
                    id: "local-diagnostic",
                    name: "Local Diagnostic Provider",
                    model: "swoosh-local-diagnostic-v1",
                    configured: true,
                    active: true,
                    status: "active"
                ),
            ],
            activeProviderID: "local-diagnostic",
            skills: [
                SkillSummary(
                    id: "bundled.review",
                    title: "Review",
                    description: "Review the current branch.",
                    category: "coding",
                    trust: "promoted"
                ),
            ]
        )
        let app = SwooshAPIServer(token: "secret", snapshot: snapshot).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/providers",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(
                uri: "/api/skills",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(
                uri: "/api/board/cards",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(
                uri: "/api/metrics",
                method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("Auth-gated chat rejects missing bearer token")
    func chatRejectsMissingBearer() async throws {
        let app = SwooshAPIServer(token: "secret").build()
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/agent/chat", method: .post) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }
}
