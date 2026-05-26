// SwooshToolsets/ConnectorLiveHealth.swift — connector live health probes

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwooshChatSDK
import SwooshTools

public struct ConnectorLiveHealth: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case verified
        case needsAction
        case failed
        case notChecked
    }

    public let state: State
    public let account: String?
    public let detail: String
    public let doctor: String?

    public var usable: Bool { state == .verified }

    public init(state: State, account: String?, detail: String, doctor: String?) {
        self.state = state
        self.account = account
        self.detail = detail
        self.doctor = doctor
    }

    public static func verified(account: String? = nil, detail: String) -> ConnectorLiveHealth {
        ConnectorLiveHealth(state: .verified, account: account, detail: detail, doctor: nil)
    }
}

public protocol ConnectorLiveHealthChecking: Sendable {
    func check(
        definition: ChatAdapterDefinition,
        sources: [String],
        dependencies: ToolDependencies
    ) async -> ConnectorLiveHealth
}

public struct URLSessionConnectorLiveHealthChecker: ConnectorLiveHealthChecking {
    public init() {}

    public func check(
        definition: ChatAdapterDefinition,
        sources: [String],
        dependencies: ToolDependencies
    ) async -> ConnectorLiveHealth {
        switch definition.kind {
        case .memory, .swoosh, .web:
            return .verified(detail: "Built-in adapter is available.")
        case .github:
            return await bearerWhoami(
                url: URL(string: "https://api.github.com/user")!,
                sources: sources,
                dependencies: dependencies,
                accountKeys: ["login", "email"],
                missing: "Add a GitHub token, then run the setup health check again."
            )
        case .discord:
            return await bearerWhoami(
                url: URL(string: "https://discord.com/api/v10/users/@me")!,
                sources: sources,
                dependencies: dependencies,
                authorizationPrefix: "Bot ",
                accountKeys: ["username", "global_name", "id"],
                missing: "Add a Discord bot token, then run the setup health check again."
            )
        case .telegram:
            guard let token = await firstSecret(sources: sources, dependencies: dependencies) else {
                return needsAction("Add a Telegram bot token, then run the setup health check again.")
            }
            return await telegramWhoami(token: token)
        case .photonIMessage, .sendblue, .blooio:
            return messagesHealth()
        case .agentMail:
            return sources.isEmpty
                ? needsAction("Add an AgentMail key or MCP server before connecting AgentMail.")
                : .verified(detail: "AgentMail credentials are present; hosted MCP validates during MCP connect.")
        case .zernioSocial:
            return sources.isEmpty
                ? needsAction("Connect an X or social-session source, then run setup health again.")
                : .verified(detail: "Browser session credentials are present; social adapter validation runs through its adapter.")
        default:
            if definition.requiresManualConfiguration {
                return needsAction("Install and configure \(definition.displayName), then run setup health again.")
            }
            return sources.isEmpty
                ? needsAction("Add credentials for \(definition.displayName), then run setup health again.")
                : .verified(detail: "Credentials are present.")
        }
    }

    private func bearerWhoami(
        url: URL,
        sources: [String],
        dependencies: ToolDependencies,
        authorizationPrefix: String = "Bearer ",
        accountKeys: [String],
        missing: String
    ) async -> ConnectorLiveHealth {
        guard let token = await firstSecret(sources: sources, dependencies: dependencies) else {
            return needsAction(missing)
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("\(authorizationPrefix)\(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return await jsonWhoami(request: request, accountKeys: accountKeys)
    }

    private func telegramWhoami(token: String) async -> ConnectorLiveHealth {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getMe") else {
            return failed("Telegram token could not form a health-check URL.")
        }
        let request = URLRequest(url: url, timeoutInterval: 8)
        let health = await jsonWhoami(request: request, accountKeys: ["username", "id"])
        guard health.state == .verified else { return health }
        return .verified(account: health.account, detail: "Telegram bot identity verified.")
    }

    private func jsonWhoami(request: URLRequest, accountKeys: [String]) async -> ConnectorLiveHealth {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return failed("Health check did not return HTTP.")
            }
            guard 200..<300 ~= http.statusCode else {
                return ConnectorLiveHealth(
                    state: .failed,
                    account: nil,
                    detail: "Health check returned HTTP \(http.statusCode).",
                    doctor: "Re-authorize this connector or replace the saved credential."
                )
            }
            let object = try JSONSerialization.jsonObject(with: data)
            let account = Self.accountLabel(in: object, keys: accountKeys)
            return .verified(account: account, detail: "Connector identity verified.")
        } catch {
            return failed("Health check failed: \(error.localizedDescription).")
        }
    }

    private func firstSecret(sources: [String], dependencies: ToolDependencies) async -> String? {
        for source in sources {
            if source.hasPrefix("environment:") {
                let key = String(source.dropFirst("environment:".count))
                if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
            if source.hasPrefix("keychain:") {
                let ref = String(source.dropFirst("keychain:".count))
                if let value = try? await dependencies.secrets.resolve(ref: ref).trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func messagesHealth() -> ConnectorLiveHealth {
        let chatDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
        if FileManager.default.isReadableFile(atPath: chatDB.path) {
            return .verified(detail: "Messages database is readable.")
        }
        return needsAction("Grant Full Disk Access to Detour, restart, then rerun the Messages scan.")
    }

    private func needsAction(_ doctor: String) -> ConnectorLiveHealth {
        ConnectorLiveHealth(state: .needsAction, account: nil, detail: "Needs setup.", doctor: doctor)
    }

    private func failed(_ detail: String) -> ConnectorLiveHealth {
        ConnectorLiveHealth(
            state: .failed,
            account: nil,
            detail: detail,
            doctor: "Open setup doctor for this connector and re-run the health check."
        )
    }

    private static func accountLabel(in object: Any, keys: [String]) -> String? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty { return value }
                if let value = dictionary[key] as? Int { return String(value) }
            }
            if let result = dictionary["result"] {
                return accountLabel(in: result, keys: keys)
            }
        }
        return nil
    }
}
