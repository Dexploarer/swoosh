// SwooshChatSDK/ChatAdapterCatalog.swift — Toggleable platform adapter catalog
import Foundation

public enum ChatAdapterKind: String, Codable, Sendable, CaseIterable, Hashable {
    case memory
    case swoosh
    case web
    case slack
    case teams
    case googleChat
    case discord
    case telegram
    case github
    case linear
    case whatsApp
    case messenger
    case beeperMatrix
    case photonIMessage
    case resendEmail
    case zernioSocial
    case agentMail = "agentmail"
    case liveblocks
    case webex
    case baileys
    case sendblue
    case blooio
    case zalo
    case mattermost
}

public enum ChatAdapterDistribution: String, Codable, Sendable, Hashable {
    case internalAdapter = "internal"
    case official
    case vendorOfficial
    case community
}

public struct ChatAdapterCredentialRequirement: Codable, Sendable, Hashable {
    public let envVar: String
    public let alternatives: [String]
    public let description: String

    public init(envVar: String, alternatives: [String] = [], description: String) {
        self.envVar = envVar
        self.alternatives = alternatives
        self.description = description
    }
}

public struct ChatAdapterDefinition: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: ChatAdapterKind
    public let displayName: String
    public let packageName: String?
    public let distribution: ChatAdapterDistribution
    public let features: ChatAdapterFeatures
    public let requiredCredentials: [ChatAdapterCredentialRequirement]
    public let canRunWithoutCredentials: Bool
    public let requiresManualConfiguration: Bool
    public let configurationNotes: [String]

    public init(
        kind: ChatAdapterKind,
        displayName: String,
        packageName: String? = nil,
        distribution: ChatAdapterDistribution = .official,
        features: ChatAdapterFeatures,
        requiredCredentials: [ChatAdapterCredentialRequirement] = [],
        canRunWithoutCredentials: Bool = false,
        requiresManualConfiguration: Bool = false,
        configurationNotes: [String] = []
    ) {
        self.id = kind.rawValue
        self.kind = kind
        self.displayName = displayName
        self.packageName = packageName
        self.distribution = distribution
        self.features = features
        self.requiredCredentials = requiredCredentials
        self.canRunWithoutCredentials = canRunWithoutCredentials
        self.requiresManualConfiguration = requiresManualConfiguration
        self.configurationNotes = configurationNotes
    }
}

public struct ChatAdapterToggle: Codable, Sendable, Hashable {
    public let kind: ChatAdapterKind
    public var enabled: Bool

    public init(kind: ChatAdapterKind, enabled: Bool) {
        self.kind = kind
        self.enabled = enabled
    }
}

public struct ChatAdapterStatus: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let definition: ChatAdapterDefinition
    public let enabled: Bool
    public let configured: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]

    public init(definition: ChatAdapterDefinition, enabled: Bool, configured: Bool, missingCredentials: [String], configurationNotes: [String] = []) {
        self.id = definition.id
        self.definition = definition
        self.enabled = enabled
        self.configured = configured
        self.missingCredentials = missingCredentials
        self.configurationNotes = configurationNotes
    }
}

public actor ChatAdapterToggleStore {
    private let url: URL
    private var loaded = false
    private var toggles: [ChatAdapterKind: Bool] = [:]

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/chat-adapters.json")
    }

    public func set(_ kind: ChatAdapterKind, enabled: Bool) throws {
        try ensureLoaded()
        toggles[kind] = enabled
        try persist()
    }

    public func isEnabled(_ kind: ChatAdapterKind) throws -> Bool {
        try ensureLoaded()
        return toggles[kind] ?? defaultEnabled(kind)
    }

    public func all() throws -> [ChatAdapterToggle] {
        try ensureLoaded()
        return ChatAdapterKind.allCases.map { ChatAdapterToggle(kind: $0, enabled: toggles[$0] ?? defaultEnabled($0)) }
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ChatAdapterToggle].self, from: data)
            toggles = Dictionary(uniqueKeysWithValues: decoded.map { ($0.kind, $0.enabled) })
        }
        loaded = true
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.swooshChat.encode(all())
        try data.write(to: url, options: .atomic)
    }

    private func defaultEnabled(_ kind: ChatAdapterKind) -> Bool {
        switch kind {
        case .memory, .swoosh, .web:
            return true
        case .slack, .teams, .googleChat, .discord, .telegram, .github, .linear, .whatsApp, .messenger,
             .beeperMatrix, .photonIMessage, .resendEmail, .zernioSocial, .liveblocks, .webex, .baileys,
             .agentMail, .sendblue, .blooio, .zalo, .mattermost:
            return false
        }
    }
}

public struct ChatAdapterCatalog: Sendable {
    public let definitions: [ChatAdapterDefinition]

    public init(definitions: [ChatAdapterDefinition] = ChatAdapterCatalog.defaultDefinitions) {
        self.definitions = definitions
    }

    public func statuses(store: ChatAdapterToggleStore, env: [String: String] = ProcessInfo.processInfo.environment) async throws -> [ChatAdapterStatus] {
        var output: [ChatAdapterStatus] = []
        for definition in definitions {
            let missing = missingCredentials(definition.requiredCredentials, in: env)
            let configured = isConfigured(
                canRunWithoutCredentials: definition.canRunWithoutCredentials,
                requiresManualConfiguration: definition.requiresManualConfiguration,
                missingCredentials: missing
            )
            let enabled = try await store.isEnabled(definition.kind)
            output.append(ChatAdapterStatus(
                definition: definition,
                enabled: enabled,
                configured: configured,
                missingCredentials: missing,
                configurationNotes: definition.configurationNotes
            ))
        }
        return output
    }

    public func definition(kind: ChatAdapterKind) -> ChatAdapterDefinition? {
        definitions.first { $0.kind == kind }
    }

    public static let defaultDefinitions: [ChatAdapterDefinition] = [
        ChatAdapterDefinition(
            kind: .memory,
            displayName: "In-memory test adapter",
            distribution: .internalAdapter,
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: true, supportsReactions: true, supportsTyping: true, supportsStreaming: true, supportsDMs: true, supportsModals: true),
            canRunWithoutCredentials: true
        ),
        ChatAdapterDefinition(
            kind: .swoosh,
            displayName: "Swoosh daemon adapter",
            distribution: .internalAdapter,
            features: ChatAdapterFeatures(supportsStreaming: true, supportsDMs: true),
            canRunWithoutCredentials: true
        ),
        ChatAdapterDefinition(
            kind: .web,
            displayName: "Web chat adapter",
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: false, supportsReactions: false, supportsTyping: true, supportsStreaming: true, supportsDMs: false, supportsModals: false, supportsCards: false),
            canRunWithoutCredentials: true
        ),
        ChatAdapterDefinition(
            kind: .slack,
            displayName: "Slack",
            packageName: "@chat-adapter/slack",
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: true, supportsReactions: true, supportsTyping: true, supportsStreaming: true, supportsDMs: true, supportsModals: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "SLACK_BOT_TOKEN", description: "Slack bot token"),
                ChatAdapterCredentialRequirement(envVar: "SLACK_SIGNING_SECRET", description: "Slack request signing secret"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .teams,
            displayName: "Microsoft Teams",
            packageName: "@chat-adapter/teams",
            features: ChatAdapterFeatures(supportsEdit: true, supportsReactions: true, supportsTyping: true, supportsStreaming: true, supportsDMs: true, supportsModals: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "TEAMS_APP_ID", description: "Teams app id"),
                ChatAdapterCredentialRequirement(envVar: "TEAMS_APP_PASSWORD", description: "Teams app password"),
                ChatAdapterCredentialRequirement(envVar: "TEAMS_APP_TENANT_ID", description: "Teams tenant id"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .googleChat,
            displayName: "Google Chat",
            packageName: "@chat-adapter/gchat",
            features: ChatAdapterFeatures(supportsEdit: true, supportsReactions: true, supportsTyping: true, supportsStreaming: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "GOOGLE_CHAT_CREDENTIALS", alternatives: ["GOOGLE_CHAT_USE_ADC"], description: "Google Chat service credentials"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .discord,
            displayName: "Discord",
            packageName: "@chat-adapter/discord",
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: true, supportsReactions: true, supportsTyping: true, supportsStreaming: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "DISCORD_BOT_TOKEN", description: "Discord bot token"),
                ChatAdapterCredentialRequirement(envVar: "DISCORD_PUBLIC_KEY", description: "Discord public key"),
                ChatAdapterCredentialRequirement(envVar: "DISCORD_APPLICATION_ID", description: "Discord application id"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .telegram,
            displayName: "Telegram",
            packageName: "@chat-adapter/telegram",
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: true, supportsReactions: false, supportsTyping: true, supportsStreaming: true, supportsDMs: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "TELEGRAM_BOT_TOKEN", description: "Telegram bot token"),
                ChatAdapterCredentialRequirement(envVar: "TELEGRAM_WEBHOOK_SECRET", description: "Telegram webhook secret"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .github,
            displayName: "GitHub Issues",
            packageName: "@chat-adapter/github",
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: true, supportsReactions: true, supportsStreaming: false),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "GITHUB_TOKEN", alternatives: ["GITHUB_APP_ID"], description: "GitHub token or app id"),
                ChatAdapterCredentialRequirement(envVar: "GITHUB_WEBHOOK_SECRET", description: "GitHub webhook secret"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .linear,
            displayName: "Linear",
            packageName: "@chat-adapter/linear",
            features: ChatAdapterFeatures(supportsEdit: true, supportsReactions: true, supportsStreaming: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "LINEAR_ACCESS_TOKEN", alternatives: ["LINEAR_API_KEY"], description: "Linear access token"),
                ChatAdapterCredentialRequirement(envVar: "LINEAR_WEBHOOK_SECRET", description: "Linear webhook secret"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .whatsApp,
            displayName: "WhatsApp Business Cloud",
            packageName: "@chat-adapter/whatsapp",
            features: ChatAdapterFeatures(supportsEdit: false, supportsDelete: false, supportsReactions: true, supportsStreaming: false, supportsDMs: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "WHATSAPP_ACCESS_TOKEN", description: "WhatsApp Cloud API token"),
                ChatAdapterCredentialRequirement(envVar: "WHATSAPP_PHONE_NUMBER_ID", description: "WhatsApp phone number id"),
                ChatAdapterCredentialRequirement(envVar: "WHATSAPP_VERIFY_TOKEN", description: "WhatsApp webhook verify token"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .messenger,
            displayName: "Messenger",
            packageName: "@chat-adapter/messenger",
            features: ChatAdapterFeatures(supportsReactions: true, supportsStreaming: false, supportsDMs: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "MESSENGER_PAGE_ACCESS_TOKEN", description: "Messenger page access token"),
                ChatAdapterCredentialRequirement(envVar: "MESSENGER_VERIFY_TOKEN", description: "Messenger webhook verify token"),
                ChatAdapterCredentialRequirement(envVar: "MESSENGER_APP_SECRET", description: "Messenger app secret"),
            ]
        ),
        ChatAdapterDefinition(
            kind: .beeperMatrix,
            displayName: "Beeper Matrix",
            packageName: "@beeper/chat-adapter-matrix",
            distribution: .vendorOfficial,
            features: ChatAdapterFeatures(supportsStreaming: true, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Vendor adapter configuration is managed by its package."]
        ),
        ChatAdapterDefinition(
            kind: .photonIMessage,
            displayName: "Photon iMessage",
            packageName: "chat-adapter-imessage",
            distribution: .vendorOfficial,
            features: ChatAdapterFeatures(supportsStreaming: true, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Supports local on-device and Photon iMessage integration."]
        ),
        ChatAdapterDefinition(
            kind: .resendEmail,
            displayName: "Resend Email",
            packageName: "@resend/chat-sdk-adapter",
            distribution: .vendorOfficial,
            features: ChatAdapterFeatures(supportsEdit: false, supportsDelete: false, supportsReactions: false, supportsStreaming: false, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Bidirectional email adapter; configure through Resend."]
        ),
        ChatAdapterDefinition(
            kind: .zernioSocial,
            displayName: "Zernio Social DMs",
            packageName: "@zernio/chat-sdk-adapter",
            distribution: .vendorOfficial,
            features: ChatAdapterFeatures(supportsStreaming: true, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Unified social DM adapter covering Instagram, Facebook, Telegram, WhatsApp, X/Twitter, Bluesky, and Reddit."]
        ),
        ChatAdapterDefinition(
            kind: .agentMail,
            displayName: "AgentMail",
            packageName: "mcp.agentmail.to",
            distribution: .vendorOfficial,
            features: ChatAdapterFeatures(supportsStreaming: false, supportsDMs: true),
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "AGENTMAIL_API_KEY", description: "AgentMail API key"),
            ],
            configurationNotes: ["Hosted MCP connector for agent-owned email."]
        ),
        ChatAdapterDefinition(
            kind: .liveblocks,
            displayName: "Liveblocks Comments",
            packageName: "@liveblocks/chat-sdk-adapter",
            distribution: .vendorOfficial,
            features: ChatAdapterFeatures(supportsStreaming: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Liveblocks room, thread, and comment configuration is managed by the vendor adapter."]
        ),
        ChatAdapterDefinition(
            kind: .webex,
            displayName: "Webex",
            packageName: "@bitbasti/chat-adapter-webex",
            distribution: .community,
            features: ChatAdapterFeatures(supportsEdit: true, supportsReactions: true, supportsStreaming: true, supportsDMs: true, supportsCards: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Community adapter with spaces, threads, and adaptive cards."]
        ),
        ChatAdapterDefinition(
            kind: .baileys,
            displayName: "Baileys WhatsApp",
            packageName: "chat-adapter-baileys",
            distribution: .community,
            features: ChatAdapterFeatures(supportsStreaming: false, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Unofficial WhatsApp adapter; configure through Baileys."]
        ),
        ChatAdapterDefinition(
            kind: .sendblue,
            displayName: "Sendblue iMessage",
            packageName: "chat-adapter-sendblue",
            distribution: .community,
            features: ChatAdapterFeatures(supportsStreaming: false, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Community iMessage adapter using Sendblue."]
        ),
        ChatAdapterDefinition(
            kind: .blooio,
            displayName: "Blooio iMessage/RCS/SMS",
            packageName: "chat-adapter-blooio",
            distribution: .community,
            features: ChatAdapterFeatures(supportsStreaming: false, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Community adapter for iMessage, RCS, and SMS."]
        ),
        ChatAdapterDefinition(
            kind: .zalo,
            displayName: "Zalo",
            packageName: "chat-adapter-zalo",
            distribution: .community,
            features: ChatAdapterFeatures(supportsStreaming: true, supportsDMs: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Community Zalo adapter."]
        ),
        ChatAdapterDefinition(
            kind: .mattermost,
            displayName: "Mattermost",
            packageName: "chat-adapter-mattermost",
            distribution: .community,
            features: ChatAdapterFeatures(supportsEdit: true, supportsDelete: true, supportsReactions: true, supportsStreaming: true),
            requiresManualConfiguration: true,
            configurationNotes: ["Community adapter with posts, reactions, and slash commands."]
        ),
    ]
}

public enum ChatStateAdapterKind: String, Codable, Sendable, CaseIterable, Hashable {
    case actantDB = "state-actantdb"
    case memory = "state-memory"
    case redis = "state-redis"
    case ioredis = "state-ioredis"
    case postgres = "state-postgres"
    case cloudflareDurableObjects = "state-cloudflare-do"
    case mysql = "state-mysql"
}

public struct ChatStateAdapterDefinition: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: ChatStateAdapterKind
    public let displayName: String
    public let packageName: String?
    public let distribution: ChatAdapterDistribution
    public let productionReady: Bool
    public let requiredCredentials: [ChatAdapterCredentialRequirement]
    public let canRunWithoutCredentials: Bool
    public let requiresManualConfiguration: Bool
    public let configurationNotes: [String]

    public init(
        kind: ChatStateAdapterKind,
        displayName: String,
        packageName: String? = nil,
        distribution: ChatAdapterDistribution,
        productionReady: Bool,
        requiredCredentials: [ChatAdapterCredentialRequirement] = [],
        canRunWithoutCredentials: Bool = false,
        requiresManualConfiguration: Bool = false,
        configurationNotes: [String] = []
    ) {
        self.id = kind.rawValue
        self.kind = kind
        self.displayName = displayName
        self.packageName = packageName
        self.distribution = distribution
        self.productionReady = productionReady
        self.requiredCredentials = requiredCredentials
        self.canRunWithoutCredentials = canRunWithoutCredentials
        self.requiresManualConfiguration = requiresManualConfiguration
        self.configurationNotes = configurationNotes
    }
}

public struct ChatStateAdapterToggle: Codable, Sendable, Hashable {
    public let kind: ChatStateAdapterKind
    public var enabled: Bool

    public init(kind: ChatStateAdapterKind, enabled: Bool) {
        self.kind = kind
        self.enabled = enabled
    }
}

public struct ChatStateAdapterStatus: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let definition: ChatStateAdapterDefinition
    public let enabled: Bool
    public let configured: Bool
    public let missingCredentials: [String]
    public let configurationNotes: [String]

    public init(definition: ChatStateAdapterDefinition, enabled: Bool, configured: Bool, missingCredentials: [String], configurationNotes: [String]) {
        self.id = definition.id
        self.definition = definition
        self.enabled = enabled
        self.configured = configured
        self.missingCredentials = missingCredentials
        self.configurationNotes = configurationNotes
    }
}

public actor ChatStateAdapterToggleStore {
    private let url: URL
    private var loaded = false
    private var toggles: [ChatStateAdapterKind: Bool] = [:]

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/chat-state-adapters.json")
    }

    public func set(_ kind: ChatStateAdapterKind, enabled: Bool) throws {
        try ensureLoaded()
        toggles[kind] = enabled
        try persist()
    }

    public func isEnabled(_ kind: ChatStateAdapterKind) throws -> Bool {
        try ensureLoaded()
        return toggles[kind] ?? defaultEnabled(kind)
    }

    public func all() throws -> [ChatStateAdapterToggle] {
        try ensureLoaded()
        return ChatStateAdapterKind.allCases.map { ChatStateAdapterToggle(kind: $0, enabled: toggles[$0] ?? defaultEnabled($0)) }
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ChatStateAdapterToggle].self, from: data)
            toggles = Dictionary(uniqueKeysWithValues: decoded.map { ($0.kind, $0.enabled) })
        }
        loaded = true
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.swooshChat.encode(all())
        try data.write(to: url, options: .atomic)
    }

    private func defaultEnabled(_ kind: ChatStateAdapterKind) -> Bool {
        switch kind {
        case .actantDB:
            return true
        case .memory, .redis, .ioredis, .postgres, .cloudflareDurableObjects, .mysql:
            return false
        }
    }
}

public struct ChatStateAdapterCatalog: Sendable {
    public let definitions: [ChatStateAdapterDefinition]

    public init(definitions: [ChatStateAdapterDefinition] = ChatStateAdapterCatalog.defaultDefinitions) {
        self.definitions = definitions
    }

    public func statuses(store: ChatStateAdapterToggleStore, env: [String: String] = ProcessInfo.processInfo.environment) async throws -> [ChatStateAdapterStatus] {
        var output: [ChatStateAdapterStatus] = []
        for definition in definitions {
            let missing = missingCredentials(definition.requiredCredentials, in: env)
            let configured = isConfigured(
                canRunWithoutCredentials: definition.canRunWithoutCredentials,
                requiresManualConfiguration: definition.requiresManualConfiguration,
                missingCredentials: missing
            )
            let enabled = try await store.isEnabled(definition.kind)
            output.append(ChatStateAdapterStatus(
                definition: definition,
                enabled: enabled,
                configured: configured,
                missingCredentials: missing,
                configurationNotes: definition.configurationNotes
            ))
        }
        return output
    }

    public static let defaultDefinitions: [ChatStateAdapterDefinition] = [
        ChatStateAdapterDefinition(
            kind: .actantDB,
            displayName: "ActantDB",
            distribution: .internalAdapter,
            productionReady: true,
            canRunWithoutCredentials: true,
            configurationNotes: ["Swoosh default durable state adapter."]
        ),
        ChatStateAdapterDefinition(
            kind: .memory,
            displayName: "Memory",
            packageName: "@chat-adapter/state-memory",
            distribution: .official,
            productionReady: false,
            canRunWithoutCredentials: true,
            configurationNotes: ["Development and test state only; not persistent across restart."]
        ),
        ChatStateAdapterDefinition(
            kind: .redis,
            displayName: "Redis",
            packageName: "@chat-adapter/state-redis",
            distribution: .official,
            productionReady: true,
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "REDIS_URL", description: "Redis connection URL"),
            ]
        ),
        ChatStateAdapterDefinition(
            kind: .ioredis,
            displayName: "ioredis",
            packageName: "@chat-adapter/state-ioredis",
            distribution: .official,
            productionReady: true,
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "REDIS_URL", description: "Redis connection URL"),
            ]
        ),
        ChatStateAdapterDefinition(
            kind: .postgres,
            displayName: "PostgreSQL",
            packageName: "@chat-adapter/state-pg",
            distribution: .official,
            productionReady: true,
            requiredCredentials: [
                ChatAdapterCredentialRequirement(envVar: "POSTGRES_URL", alternatives: ["DATABASE_URL"], description: "PostgreSQL connection URL"),
            ]
        ),
        ChatStateAdapterDefinition(
            kind: .cloudflareDurableObjects,
            displayName: "Cloudflare Durable Objects",
            packageName: "chat-state-cloudflare-do",
            distribution: .community,
            productionReady: true,
            requiresManualConfiguration: true,
            configurationNotes: ["Community state adapter with SQLite-backed durable objects."]
        ),
        ChatStateAdapterDefinition(
            kind: .mysql,
            displayName: "MySQL",
            packageName: "chat-state-mysql",
            distribution: .community,
            productionReady: true,
            requiresManualConfiguration: true,
            configurationNotes: ["Community MySQL state adapter."]
        ),
    ]
}

private func missingCredentials(
    _ requirements: [ChatAdapterCredentialRequirement],
    in env: [String: String]
) -> [String] {
    requirements
        .filter { requirement in
            ([requirement.envVar] + requirement.alternatives).allSatisfy { (env[$0] ?? "").isEmpty }
        }
        .map(\.envVar)
}

private func isConfigured(
    canRunWithoutCredentials: Bool,
    requiresManualConfiguration: Bool,
    missingCredentials: [String]
) -> Bool {
    canRunWithoutCredentials || (!requiresManualConfiguration && missingCredentials.isEmpty)
}

extension JSONEncoder {
    static var swooshChat: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
