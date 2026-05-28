// Tests/SwooshAPITests/BearerGateTests.swift — 0.1A
//
// Wire-level coverage for the /api/* auth gate at the server boundary
// (AuthMiddlewareTests covers the matcher function; this exercises the
// built app). Two regimes:
//   • token == nil  → DenyAllMiddleware shadow-mounts the whole /api/* tree
//     and refuses every request (401), so an accidentally-public daemon
//     can't act even if it binds 0.0.0.0.
//   • token set     → BearerAuthMiddleware: missing/wrong bearer → 401,
//     correct bearer → the route runs.

import HummingbirdTesting
import HTTPTypes
import Testing
import Foundation
@testable import SwooshAPI
import SwooshClient

@Suite("Bearer auth gate")
struct BearerGateTests {

    /// A minimal route the gate sits in front of.
    private func sources() -> SwooshAPIRuntimeSources {
        SwooshAPIRuntimeSources(
            firewallGrants: { FirewallResponse(granted: ["toolRead"], denied: []) }
        )
    }

    @Test("token == nil → DenyAll refuses /api/* even with a bearer header")
    func nilTokenDeniesAll() async throws {
        let app = SwooshAPIServer(token: nil, runtimeSources: sources()).build()
        try await app.test(.router) { client in
            // Even a well-formed bearer is refused — the tree is shadow-mounted.
            try await client.execute(
                uri: "/api/firewall/grants", method: .get,
                headers: [.authorization: "Bearer anything"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("token set + missing bearer → 401")
    func missingBearerRejected() async throws {
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources()).build()
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/firewall/grants", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("token set + wrong bearer → 401")
    func wrongBearerRejected() async throws {
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources()).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/firewall/grants", method: .get,
                headers: [.authorization: "Bearer not-the-secret"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("token set + correct bearer → route runs (200)")
    func correctBearerAllowed() async throws {
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources()).build()
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/firewall/grants", method: .get,
                headers: [.authorization: "Bearer secret"]
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("public /health is reachable without a bearer")
    func healthIsPublic() async throws {
        let app = SwooshAPIServer(token: "secret", runtimeSources: sources()).build()
        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }
}
