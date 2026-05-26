// DetourHomeDaemonClient.swift — shared daemon client construction for Detour home (0.5A)

import Foundation

enum DetourHomeDaemonClient {
    static var baseURL: URL {
        HostStore.current ?? URL(string: "http://127.0.0.1:8787")!
    }

    static func make() throws -> SwooshAPIClient {
        try SwooshAPIClient(baseURL: baseURL, token: bearerToken())
    }

    @MainActor
    static func makeEnsuringDaemon() async throws -> SwooshAPIClient {
        try await DetourDaemonSupervisor.shared.ensureRunning()
        return try make()
    }

    static func display(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return DetourSetupInsightRedaction.display(message)
        }
        return DetourSetupInsightRedaction.display(error.localizedDescription)
    }

    private static func bearerToken() throws -> String {
        if let token = TokenStore.load(), !token.isEmpty {
            return token
        }
        let tokenURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
            .appendingPathComponent("api_token", isDirectory: false)
        let token = try String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            throw DetourHomeDaemonClientError.missingToken
        }
        return token
    }
}

private enum DetourHomeDaemonClientError: LocalizedError {
    case missingToken

    var errorDescription: String? {
        "swooshd is not paired with this Mac app yet."
    }
}
