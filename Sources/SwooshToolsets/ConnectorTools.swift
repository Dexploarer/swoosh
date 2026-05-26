// SwooshToolsets/ConnectorTools.swift — Connector runtime status tools
import Foundation
import SwooshChatSDK
import SwooshTools

public struct ConnectorStatusInput: Codable, Sendable {
    public let connectorID: String?
    public let includeAll: Bool?

    public init(connectorID: String? = nil, includeAll: Bool? = nil) {
        self.connectorID = connectorID
        self.includeAll = includeAll
    }
}

public struct ConnectorStatusOutput: Codable, Sendable {
    public let success: Bool
    public let requestedConnectorID: String?
    public let connectors: [ConnectorRuntimeStatus]
    public let stateAdapters: [ConnectorStateRuntimeStatus]
    public let doctor: [String]
}

public struct ConnectorRuntimeStatus: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let packageName: String?
    public let enabled: Bool
    public let configured: Bool
    public let credentialBacked: Bool
    public let usable: Bool
    public let missingCredentials: [String]
    public let credentialSources: [String]
    public let configurationNotes: [String]
    public let features: ChatAdapterFeatures
    public let liveHealth: ConnectorLiveHealth
}

public struct ConnectorStateRuntimeStatus: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let packageName: String?
    public let enabled: Bool
    public let configured: Bool
    public let productionReady: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]
}

public struct ConnectorStatusTool: SwooshTool {
    public typealias Input = ConnectorStatusInput
    public typealias Output = ConnectorStatusOutput

    public static let name: ToolName = "connector.status"
    public static let displayName = "Connector Status"
    public static let description = "List configured message connectors and report whether the agent can use them"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.connectors

    private let dependencies: ToolDependencies
    private let adapterCatalog: ChatAdapterCatalog
    private let stateCatalog: ChatStateAdapterCatalog
    private let adapterStore: ChatAdapterToggleStore
    private let stateStore: ChatStateAdapterToggleStore
    private let liveHealthChecker: any ConnectorLiveHealthChecking

    public init(
        dependencies: ToolDependencies,
        adapterCatalog: ChatAdapterCatalog = ChatAdapterCatalog(),
        stateCatalog: ChatStateAdapterCatalog = ChatStateAdapterCatalog(),
        adapterStore: ChatAdapterToggleStore = ChatAdapterToggleStore(),
        stateStore: ChatStateAdapterToggleStore = ChatStateAdapterToggleStore(),
        liveHealthChecker: any ConnectorLiveHealthChecking = URLSessionConnectorLiveHealthChecker()
    ) {
        self.dependencies = dependencies
        self.adapterCatalog = adapterCatalog
        self.stateCatalog = stateCatalog
        self.adapterStore = adapterStore
        self.stateStore = stateStore
        self.liveHealthChecker = liveHealthChecker
    }

    public func call(_ input: ConnectorStatusInput, context: ToolContext) async throws -> ConnectorStatusOutput {
        let requestedIDs = connectorIDs(for: input.connectorID)
        let env = ProcessInfo.processInfo.environment
        let adapterStatuses = try await adapterCatalog.statuses(store: adapterStore, env: env)
        let stateStatuses = try await stateCatalog.statuses(store: stateStore, env: env)
        var connectorOutputs: [ConnectorRuntimeStatus] = []
        var doctor: [String] = []

        for status in adapterStatuses where shouldInclude(status.id, requestedIDs: requestedIDs, includeAll: input.includeAll ?? false) {
            let sources = await credentialSources(for: status.definition)
            let credentialBacked = !sources.isEmpty
            let liveHealth = status.enabled
                ? await liveHealthChecker.check(definition: status.definition, sources: sources, dependencies: dependencies)
                : ConnectorLiveHealth(state: .notChecked, account: nil, detail: "Connector is disabled.", doctor: nil)
            let usable = status.enabled && liveHealth.usable
            if status.enabled && !usable {
                doctor.append(liveHealth.doctor ?? "\(status.definition.displayName) is enabled but did not pass live health.")
            }
            connectorOutputs.append(ConnectorRuntimeStatus(
                id: status.id,
                displayName: status.definition.displayName,
                packageName: status.definition.packageName,
                enabled: status.enabled,
                configured: status.configured,
                credentialBacked: credentialBacked,
                usable: usable,
                missingCredentials: credentialBacked ? [] : status.missingCredentials,
                credentialSources: sources,
                configurationNotes: status.configurationNotes,
                features: status.definition.features,
                liveHealth: liveHealth
            ))
        }

        let stateOutputs = stateStatuses
            .filter { shouldInclude($0.id, requestedIDs: requestedIDs, includeAll: input.includeAll ?? false) }
            .map { status in
                ConnectorStateRuntimeStatus(
                    id: status.id,
                    displayName: status.definition.displayName,
                    packageName: status.definition.packageName,
                    enabled: status.enabled,
                    configured: status.configured,
                    productionReady: status.definition.productionReady,
                    missingCredentials: status.missingCredentials,
                    configurationNotes: status.configurationNotes
                )
            }

        if let requested = input.connectorID, connectorOutputs.isEmpty && stateOutputs.isEmpty {
            doctor.append("No connector or state adapter matched '\(requested)'.")
        }
        if input.connectorID != nil,
           !connectorOutputs.contains(where: \.usable),
           !stateOutputs.contains(where: { $0.enabled && $0.configured }) {
            doctor.append("The requested connector is not usable yet.")
        }

        return ConnectorStatusOutput(
            success: doctor.isEmpty,
            requestedConnectorID: input.connectorID,
            connectors: connectorOutputs.sorted { $0.displayName < $1.displayName },
            stateAdapters: stateOutputs.sorted { $0.displayName < $1.displayName },
            doctor: doctor
        )
    }

    private func shouldInclude(_ id: String, requestedIDs: Set<String>, includeAll: Bool) -> Bool {
        includeAll || requestedIDs.isEmpty || requestedIDs.contains(id)
    }

    private func connectorIDs(for raw: String?) -> Set<String> {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return []
        }
        switch raw {
        case "discord":
            return ["discord"]
        case "telegram":
            return ["telegram"]
        case "github", "github-issues":
            return ["github"]
        case "agentmail", "mail", "email":
            return ["agentmail"]
        case "imessage", "messages":
            return ["photonIMessage", "sendblue", "blooio"]
        case "photonimessage", "photon-imessage":
            return ["photonIMessage"]
        case "x", "twitter":
            return ["zernioSocial"]
        case "slack":
            return ["slack"]
        case "linear":
            return ["linear"]
        case "state", "state-actantdb", "actantdb":
            return ["state-actantdb"]
        default:
            return [raw]
        }
    }

    private func credentialSources(for definition: ChatAdapterDefinition) async -> [String] {
        var sources: [String] = []
        let keys = Set(definition.requiredCredentials.flatMap { [$0.envVar] + $0.alternatives } + credentialAliases(for: definition.kind))
        for key in keys.sorted() {
            if let value = ProcessInfo.processInfo.environment[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sources.append("environment:\(key)")
            }
            for ref in secretRefs(for: key) {
                if await secretExists(ref) {
                    sources.append("keychain:\(ref)")
                }
            }
        }
        return Array(Set(sources)).sorted()
    }

    private func secretExists(_ ref: String) async -> Bool {
        do {
            return try await !dependencies.secrets.resolve(ref: ref).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    private func credentialAliases(for kind: ChatAdapterKind) -> [String] {
        switch kind {
        case .discord:
            return ["DISCORD_API_TOKEN"]
        case .github:
            return ["GITHUB_USER_PAT", "GITHUB_AGENT_PAT"]
        case .slack:
            return ["SLACK_API_TOKEN"]
        case .linear:
            return ["LINEAR_API_KEY"]
        case .agentMail:
            return ["AGENTMAIL_API_KEY"]
        case .zernioSocial:
            return ["X_AUTH_TOKEN", "X_CT0"]
        default:
            return []
        }
    }

    private func secretRefs(for key: String) -> [String] {
        switch key {
        case "DISCORD_BOT_TOKEN", "DISCORD_API_TOKEN":
            return ["discord.bot_token", "legacy.DISCORD_BOT_TOKEN", "legacy.DISCORD_API_TOKEN"]
        case "TELEGRAM_BOT_TOKEN":
            return ["telegram.bot_token", "legacy.TELEGRAM_BOT_TOKEN"]
        case "GITHUB_TOKEN", "GITHUB_USER_PAT":
            return ["github.user_pat", "legacy.GITHUB_TOKEN", "legacy.GITHUB_USER_PAT"]
        case "GITHUB_AGENT_PAT":
            return ["github.agent_pat", "legacy.GITHUB_AGENT_PAT"]
        case "SLACK_BOT_TOKEN", "SLACK_API_TOKEN":
            return ["slack.bot_token", "legacy.SLACK_BOT_TOKEN", "legacy.SLACK_API_TOKEN"]
        case "SLACK_TEAM_ID":
            return ["slack.team_id", "legacy.SLACK_TEAM_ID"]
        case "SLACK_CHANNEL_IDS":
            return ["slack.channel_ids", "legacy.SLACK_CHANNEL_IDS"]
        case "LINEAR_API_KEY", "LINEAR_ACCESS_TOKEN":
            return ["linear.api_key", "legacy.LINEAR_API_KEY", "legacy.LINEAR_ACCESS_TOKEN"]
        case "AGENTMAIL_API_KEY":
            return ["agentmail.api_key", "legacy.AGENTMAIL_API_KEY"]
        case "X_AUTH_TOKEN":
            return ["x.auth_token", "legacy.X_AUTH_TOKEN"]
        case "X_CT0":
            return ["x.ct0", "legacy.X_CT0"]
        default:
            return ["legacy.\(key)"]
        }
    }
}
