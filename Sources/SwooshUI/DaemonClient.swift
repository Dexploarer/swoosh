// SwooshUI/DaemonClient.swift — 0.9R Shared daemon client resolution

import Foundation
import SwooshClient
import SwooshConfig

public struct SwooshDaemonEndpoint: Sendable {
    public let baseURL: URL
    public let token: String?

    public init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }
}

public enum SwooshDaemonClient {
    public static func endpoint() -> SwooshDaemonEndpoint? {
        let config = SwooshConfigStore()
        let runtime = try? config.load(SwooshRuntimeConfig.self)
        let host = runtime?.daemonHost ?? "127.0.0.1"
        let port = runtime?.daemonPort ?? 8787
        let configuredURL = URL(string: "http://\(host):\(port)")
        let baseURL = HostStore.current ?? configuredURL
        guard let baseURL else { return nil }
        return SwooshDaemonEndpoint(baseURL: baseURL, token: token(config: config))
    }

    public static func client() -> SwooshAPIClient? {
        guard let endpoint = endpoint() else { return nil }
        return SwooshAPIClient(baseURL: endpoint.baseURL, token: endpoint.token)
    }

    public static func token(config: SwooshConfigStore = SwooshConfigStore()) -> String? {
        // File-based token from swooshd takes priority — it's what
        // the daemon writes on startup. Keychain may hold a stale value
        // from a previous session.
        if let fileToken = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fileToken.isEmpty {
            return fileToken
        }
        if let token = TokenStore.load(), !token.isEmpty {
            return token
        }
        return nil
    }

    public static func health() async -> Bool {
        guard let client = client() else { return false }
        return await client.health()
    }
}
