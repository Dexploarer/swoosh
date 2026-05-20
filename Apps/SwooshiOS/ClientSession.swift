// Apps/SwooshiOS/ClientSession.swift — App-wide pairing + client state
//
// Holds the current host URL and bearer token (read from HostStore +
// TokenStore on app launch) and produces a SwooshAPIClient pre-configured
// with both. The model is `@Observable` so every screen that reads from
// the environment re-renders on pair / unpair.

import Foundation
import Observation
import SwooshClient

@MainActor
@Observable
final class ClientSession {
    private(set) var host: URL?
    private(set) var hasToken: Bool = false
    private(set) var lastHealth: HealthState = .unknown
    private(set) var agentStatus: AgentStatusResponse?

    enum HealthState: Sendable, Equatable {
        case unknown
        case ok
        case unreachable
    }

    /// Build a one-shot API client against the current pairing. Returns nil
    /// when the user hasn't paired yet — callers should route to Settings.
    func client() -> SwooshAPIClient? {
        guard let host else { return nil }
        return SwooshAPIClient(baseURL: host, token: TokenStore.load())
    }

    /// Build the executor the chat surface actually calls. Today this is
    /// always `RemoteKernelExecutor` (the Mac is the kernel host). When
    /// the iOS-local kernel ships, this is where the routing logic lives
    /// — pick `LocalKernelExecutor` when offline, remote when paired and
    /// reachable.
    func executor() -> (any SwooshExecutor)? {
        client().map(RemoteKernelExecutor.init)
    }

    var isPaired: Bool { host != nil && hasToken }

    /// Refresh from persistent stores and re-probe the daemon's health
    /// endpoint. Called on launch and after Settings saves.
    func refresh() async {
        host = HostStore.current
        hasToken = TokenStore.load() != nil

        guard let client = client() else {
            lastHealth = .unknown
            agentStatus = nil
            return
        }
        let healthy = await client.health()
        guard healthy else {
            lastHealth = .unreachable
            agentStatus = nil
            return
        }
        do {
            agentStatus = try await client.agentStatus()
            lastHealth = .ok
        } catch {
            agentStatus = nil
            lastHealth = .unreachable
        }
    }

    /// Persist a new pairing and re-probe.
    func pair(host: URL, token: String) async throws {
        try TokenStore.save(token)
        HostStore.current = host
        await refresh()
    }

    /// Wipe the stored pairing.
    func unpair() async {
        TokenStore.delete()
        HostStore.current = nil
        await refresh()
    }
}
