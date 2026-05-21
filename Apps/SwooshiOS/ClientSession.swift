// Apps/SwooshiOS/ClientSession.swift — App-wide pairing + client state
//
// Holds the current host URL and bearer token (read from HostStore +
// TokenStore on app launch) and produces a SwooshAPIClient pre-configured
// with both. The model is `@Observable` so every screen that reads from
// the environment re-renders on pair / unpair.

import Foundation
import Observation
import SwooshClient
#if os(iOS)
import SwooshLocalLLM
#endif

@MainActor
@Observable
final class ClientSession {
    static let defaultSessionID = "ios-default"

    private(set) var host: URL?
    private(set) var hasToken: Bool = false
    private(set) var lastHealth: HealthState = .unknown
    private(set) var agentStatus: AgentStatusResponse?
    private(set) var runtimeConfig: RuntimeConfigResponse?
    private(set) var sessionID: String = ClientSession.defaultSessionID

    /// User preference. When true and the daemon is unreachable, the
    /// chat path falls through to the on-device LiteRT model.
    /// Persisted via `UserDefaults` under `swoosh.localFallback`.
    var localFallbackEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "swoosh.localFallback") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "swoosh.localFallback") }
    }

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

    /// Build the executor the chat surface actually calls. Layered:
    ///   1. `RemoteKernelExecutor` hits `/api/agent/chat` on the Mac.
    ///   2. `FallbackExecutor` (iOS only) falls through to the on-device
    ///      LiteRT model when the Mac is unreachable AND the user has
    ///      `localFallbackEnabled = true`.
    ///   3. `CachedExecutor` persists every turn and queues sends that
    ///      hit "everything offline" for later replay.
    func executor() -> (any SwooshExecutor)? {
        guard let client = client() else { return nil }
        let remote = RemoteKernelExecutor(client: client)

        #if os(iOS)
        let routedRemote: any SwooshExecutor = MainActor.assumeIsolated {
            FallbackExecutor(
                remote: remote,
                enableLocalFallback: localFallbackEnabled
            )
        }
        #else
        let routedRemote: any SwooshExecutor = remote
        #endif

        do {
            return try CachedExecutor(inner: routedRemote, sessionID: sessionID)
        } catch {
            // App-support unavailable — fall back to raw routed remote
            // so the user can still chat (no offline buffer, but no
            // broken UI).
            return routedRemote
        }
    }

    var isPaired: Bool { host != nil && hasToken }

    /// Refresh from persistent stores and re-probe the daemon's health
    /// endpoint. Called on launch and after Settings saves.
    func refresh() async {
        seedPairing()
        host = HostStore.current
        hasToken = TokenStore.load() != nil

        guard let client = client() else {
            lastHealth = .unknown
            agentStatus = nil
            runtimeConfig = nil
            return
        }
        let healthy = await client.health()
        guard healthy else {
            lastHealth = .unreachable
            agentStatus = nil
            runtimeConfig = nil
            return
        }
        do {
            agentStatus = try await client.agentStatus()
            runtimeConfig = try? await client.runtimeConfig()
            lastHealth = .ok
        } catch {
            agentStatus = nil
            runtimeConfig = nil
            lastHealth = .unreachable
        }
    }

    /// Persist a new pairing and re-probe.
    func pair(host: URL, token: String) async throws {
        try TokenStore.save(token)
        HostStore.current = host
        await refresh()
    }

    func pair(url: URL) async {
        guard url.scheme == "swoosh",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let hostRaw = components.queryItems?.first(where: { $0.name == "host" })?.value,
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let host = URL(string: hostRaw),
              !token.isEmpty else { return }

        try? TokenStore.save(token)
        HostStore.current = host
        await refresh()
    }

    /// Wipe the stored pairing.
    func unpair() async {
        TokenStore.delete()
        HostStore.current = nil
        await refresh()
    }

    private func seedPairing() {
        let environment = ProcessInfo.processInfo.environment
        if let hostRaw = environment["SWOOSH_PAIR_HOST"],
           let token = environment["SWOOSH_PAIR_TOKEN"],
           let host = URL(string: hostRaw),
           !token.isEmpty {
            try? TokenStore.save(token)
            HostStore.current = host
        }

        guard let seed = loadPairingSeed() else { return }
        try? TokenStore.save(seed.token)
        HostStore.current = seed.host
    }

    private func loadPairingSeed() -> PairingSeed? {
        let manager = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var candidates = [
            home.appendingPathComponent("swoosh-pairing.json"),
            home.appendingPathComponent("Documents"),
        ]
        if let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.insert(documents.appendingPathComponent("swoosh-pairing.json"), at: 0)
        }

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let seed = try? JSONDecoder().decode(PairingSeed.self, from: data) else { continue }
            try? manager.removeItem(at: url)
            return seed
        }
        return nil
    }
}

private struct PairingSeed: Decodable {
    let host: URL
    let token: String
}
