// SwooshActantBackend/ActantBackend.swift — ActantDB-backed adapters for SwooshCore protocols
//
// Strategy:
//   - SessionStoring     → ActantDB commands (append_user_message / append_agent_message)
//                          + events query (loadTranscript reconstructs from the ledger)
//   - ResponseAuditing   → emit an append_agent_message carrying the audit JSON,
//                          so the audit record is part of the same hash-chained event stream
//                          that Studio + replay see
//   - MemoryContextLoading / SetupReportLoading / PermissionSummarizing remain on
//     SwooshStorage (SQLite) for v0 — ActantDB lacks a `GET /v1/memories` query endpoint
//     today; switching them needs a follow-up server change. See merc/Docs/V0Architecture.md.

import Foundation
import ActantDB
import SwooshCore

/// Configuration for the ActantDB-backed adapters. One per process; share the
/// `ActantClient` across adapters (it's a Sendable struct, cheap to copy).
public struct ActantBackendConfig: Sendable {
    public let client: ActantClient
    public let workspaceID: String
    public let actorID: String

    public init(client: ActantClient, workspaceID: String, actorID: String) {
        self.client = client
        self.workspaceID = workspaceID
        self.actorID = actorID
    }

    /// Convenience: build from raw values.
    public init(
        baseURL: URL,
        workspaceID: String = "ws_default",
        actorID: String = "act_system",
        token: String? = nil
    ) {
        self.init(
            client: ActantClient(baseURL: baseURL, token: token),
            workspaceID: workspaceID,
            actorID: actorID
        )
    }

    /// Verify the server is reachable + ready. Call at swooshd startup before
    /// the kernel starts accepting requests.
    public func waitForReady(timeout: TimeInterval = 10, pollInterval: TimeInterval = 0.25) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: (any Error)?
        while Date() < deadline {
            do {
                let r = try await client.healthzReady()
                if r.isHealthy { return }
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw lastError ?? ActantError.transport("ActantDB server did not become ready within \(timeout)s")
    }
}
