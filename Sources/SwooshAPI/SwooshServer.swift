// SwooshAPI/SwooshServer.swift — HTTP API + WebSocket server
//
// Hummingbird-based API server for external integrations, web dashboard,
// and WebSocket streaming of agent responses.

import Foundation
import Hummingbird

// ═══════════════════════════════════════════════════════════════════
// MARK: - API server
// ═══════════════════════════════════════════════════════════════════

/// Swoosh HTTP API server using Hummingbird.
public struct SwooshAPIServer {
    private let port: Int
    private let hostname: String

    public init(port: Int = 8787, hostname: String = "127.0.0.1") {
        self.port = port; self.hostname = hostname
    }

    /// Build the Hummingbird application with all routes.
    public func build() -> some ApplicationProtocol {
        let router = Router()

        // Health
        router.get("/health") { _, _ in "ok" }
        router.get("/api/version") { _, _ in "{\"version\":\"0.9P\",\"name\":\"Swoosh\"}" }

        // Agent
        router.post("/api/agent/chat") { request, _ -> String in
            // Placeholder — wire to AgentKernel
            return "{\"response\":\"Agent chat endpoint ready\"}"
        }
        router.get("/api/agent/status") { _, _ in
            "{\"status\":\"idle\",\"model\":null,\"session\":null}"
        }

        // Providers
        router.get("/api/providers") { _, _ in
            "{\"providers\":[],\"count\":0}"
        }
        router.get("/api/providers/status") { _, _ in
            "{\"healthy\":0,\"total\":0}"
        }

        // Board
        router.get("/api/board/cards") { _, _ in "{\"cards\":[],\"count\":0}" }
        router.get("/api/board/lanes") { _, _ in "{\"lanes\":[],\"count\":0}" }

        // Observability
        router.get("/api/metrics") { _, _ in "{\"tokens\":0,\"cost\":0,\"traces\":0}" }
        router.get("/api/usage") { _, _ in "{\"today\":{\"tokens\":0,\"cost\":0}}" }

        // Skills
        router.get("/api/skills") { _, _ in "{\"skills\":[],\"count\":0}" }

        let app = Application(router: router, configuration: .init(address: .hostname(hostname, port: port)))
        return app
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - API error
// ═══════════════════════════════════════════════════════════════════

public enum APIError: Error, Sendable {
    case notFound(String)
    case unauthorized
    case badRequest(String)
    case internalError(String)
}
