// Apps/SwooshiOS/ChannelCatalog.swift — Local mirror of ChatAdapterCatalog
//
// SwooshChatSDK (the daemon-side catalog at
// Sources/SwooshChatSDK/ChatAdapterCatalog.swift) isn't an iOS-safe
// import, so the iOS app keeps a static mirror of the adapter list
// here. Once the daemon exposes `/api/agent/channels` we swap this for
// a live wire fetch; the field layout matches one-for-one.

import Foundation

enum ChannelDistribution: String, Codable, Sendable {
    case internalAdapter
    case official
    case vendorOfficial
    case community

    var displayName: String {
        switch self {
        case .internalAdapter: "Internal"
        case .official:        "Official"
        case .vendorOfficial:  "Vendor"
        case .community:       "Community"
        }
    }
}

enum ChannelCategory: String, CaseIterable, Identifiable {
    case team
    case direct
    case developer
    case email
    case bridge
    case socialAggregator
    case web
    case internalSurface

    var id: String { rawValue }

    var title: String {
        switch self {
        case .team:             "Team chat"
        case .direct:           "Direct messaging"
        case .developer:        "Developer"
        case .email:            "Email & notifications"
        case .bridge:           "Bridges & gateways"
        case .socialAggregator: "Social aggregators"
        case .web:              "Web & embedded"
        case .internalSurface:  "Internal"
        }
    }
}

struct ChannelCatalogEntry: Identifiable, Hashable {
    let kindRawValue: String  // matches ChatAdapterKind.rawValue
    let displayName: String
    let packageName: String?
    let distribution: ChannelDistribution
    let category: ChannelCategory
    let description: String
    let credentialEnvVars: [String]

    var id: String { kindRawValue }
}

enum ChannelCatalog {
    static let entries: [ChannelCatalogEntry] = [
        // Internal
        ChannelCatalogEntry(
            kindRawValue: "memory",
            displayName: "In-memory test adapter",
            packageName: nil,
            distribution: .internalAdapter,
            category: .internalSurface,
            description: "Local-only adapter used by tests and dry runs. No external credentials.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "swoosh",
            displayName: "Swoosh daemon adapter",
            packageName: nil,
            distribution: .internalAdapter,
            category: .internalSurface,
            description: "Native swooshd transport for first-party clients (this iPhone, the menu-bar app).",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "web",
            displayName: "Web chat adapter",
            packageName: nil,
            distribution: .official,
            category: .web,
            description: "Embeddable web chat surface served from swooshd.",
            credentialEnvVars: []
        ),

        // Team chat
        ChannelCatalogEntry(
            kindRawValue: "slack",
            displayName: "Slack",
            packageName: "@chat-adapter/slack",
            distribution: .official,
            category: .team,
            description: "Slack bot with edits, deletes, reactions, typing, streaming, DMs, and modals.",
            credentialEnvVars: ["SLACK_BOT_TOKEN", "SLACK_SIGNING_SECRET"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "teams",
            displayName: "Microsoft Teams",
            packageName: "@chat-adapter/teams",
            distribution: .official,
            category: .team,
            description: "Teams bot supporting edits, reactions, streaming, DMs, and adaptive cards.",
            credentialEnvVars: ["TEAMS_APP_ID", "TEAMS_APP_PASSWORD", "TEAMS_APP_TENANT_ID"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "googleChat",
            displayName: "Google Chat",
            packageName: "@chat-adapter/gchat",
            distribution: .official,
            category: .team,
            description: "Google Chat with edits, reactions, typing, and streaming.",
            credentialEnvVars: ["GOOGLE_CHAT_CREDENTIALS"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "discord",
            displayName: "Discord",
            packageName: "@chat-adapter/discord",
            distribution: .official,
            category: .team,
            description: "Discord bot with edits, deletes, reactions, typing, and streaming.",
            credentialEnvVars: ["DISCORD_BOT_TOKEN", "DISCORD_PUBLIC_KEY", "DISCORD_APPLICATION_ID"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "mattermost",
            displayName: "Mattermost",
            packageName: "chat-adapter-mattermost",
            distribution: .community,
            category: .team,
            description: "Community adapter — posts, reactions, slash commands.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "webex",
            displayName: "Webex",
            packageName: "@bitbasti/chat-adapter-webex",
            distribution: .community,
            category: .team,
            description: "Community Webex adapter — spaces, threads, and adaptive cards.",
            credentialEnvVars: []
        ),

        // Direct messaging
        ChannelCatalogEntry(
            kindRawValue: "telegram",
            displayName: "Telegram",
            packageName: "@chat-adapter/telegram",
            distribution: .official,
            category: .direct,
            description: "Telegram bot with edits, deletes, typing, streaming, and DMs.",
            credentialEnvVars: ["TELEGRAM_BOT_TOKEN"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "whatsApp",
            displayName: "WhatsApp Business Cloud",
            packageName: "@chat-adapter/whatsapp",
            distribution: .official,
            category: .direct,
            description: "Meta's WhatsApp Cloud API — reactions and DMs.",
            credentialEnvVars: ["WHATSAPP_ACCESS_TOKEN", "WHATSAPP_PHONE_NUMBER_ID", "WHATSAPP_VERIFY_TOKEN"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "messenger",
            displayName: "Messenger",
            packageName: "@chat-adapter/messenger",
            distribution: .official,
            category: .direct,
            description: "Facebook Messenger page integration with reactions and DMs.",
            credentialEnvVars: ["MESSENGER_PAGE_ACCESS_TOKEN", "MESSENGER_VERIFY_TOKEN", "MESSENGER_APP_SECRET"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "photonIMessage",
            displayName: "Photon iMessage",
            packageName: "chat-adapter-imessage",
            distribution: .vendorOfficial,
            category: .direct,
            description: "On-device + Photon iMessage. Configured through the vendor package.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "beeperMatrix",
            displayName: "Beeper Matrix",
            packageName: "@beeper/chat-adapter-matrix",
            distribution: .vendorOfficial,
            category: .direct,
            description: "Matrix via Beeper — streaming and DMs. Configured through the vendor package.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "zalo",
            displayName: "Zalo",
            packageName: "chat-adapter-zalo",
            distribution: .community,
            category: .direct,
            description: "Community Zalo adapter with streaming and DMs.",
            credentialEnvVars: []
        ),

        // Bridges
        ChannelCatalogEntry(
            kindRawValue: "baileys",
            displayName: "Baileys WhatsApp",
            packageName: "chat-adapter-baileys",
            distribution: .community,
            category: .bridge,
            description: "Unofficial WhatsApp adapter via Baileys.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "sendblue",
            displayName: "Sendblue iMessage",
            packageName: "chat-adapter-sendblue",
            distribution: .community,
            category: .bridge,
            description: "Community iMessage adapter using Sendblue's gateway.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "blooio",
            displayName: "Blooio iMessage / RCS / SMS",
            packageName: "chat-adapter-blooio",
            distribution: .community,
            category: .bridge,
            description: "Community adapter for iMessage, RCS, and SMS via Blooio.",
            credentialEnvVars: []
        ),

        // Developer
        ChannelCatalogEntry(
            kindRawValue: "github",
            displayName: "GitHub Issues",
            packageName: "@chat-adapter/github",
            distribution: .official,
            category: .developer,
            description: "GitHub issues + comments — edits, deletes, and reactions.",
            credentialEnvVars: ["GITHUB_TOKEN", "GITHUB_WEBHOOK_SECRET"]
        ),
        ChannelCatalogEntry(
            kindRawValue: "linear",
            displayName: "Linear",
            packageName: "@chat-adapter/linear",
            distribution: .official,
            category: .developer,
            description: "Linear issues and comments — edits, reactions, streaming.",
            credentialEnvVars: ["LINEAR_ACCESS_TOKEN", "LINEAR_WEBHOOK_SECRET"]
        ),

        // Email & notifications
        ChannelCatalogEntry(
            kindRawValue: "resendEmail",
            displayName: "Resend Email",
            packageName: "@resend/chat-sdk-adapter",
            distribution: .vendorOfficial,
            category: .email,
            description: "Bidirectional email — configured through Resend.",
            credentialEnvVars: []
        ),
        ChannelCatalogEntry(
            kindRawValue: "liveblocks",
            displayName: "Liveblocks Comments",
            packageName: "@liveblocks/chat-sdk-adapter",
            distribution: .vendorOfficial,
            category: .email,
            description: "Liveblocks rooms, threads, and comments.",
            credentialEnvVars: []
        ),

        // Social aggregator
        ChannelCatalogEntry(
            kindRawValue: "zernioSocial",
            displayName: "Zernio Social DMs",
            packageName: "@zernio/chat-sdk-adapter",
            distribution: .vendorOfficial,
            category: .socialAggregator,
            description: "Unified social DM bridge — Instagram, Facebook, Telegram, WhatsApp, X / Twitter, Bluesky, Reddit.",
            credentialEnvVars: []
        ),
    ]

    static var byCategory: [(ChannelCategory, [ChannelCatalogEntry])] {
        ChannelCategory.allCases.compactMap { category in
            let bucket = entries.filter { $0.category == category }
            return bucket.isEmpty ? nil : (category, bucket)
        }
    }

    /// Static catalog keyed by adapter id (`ChatAdapterKind.rawValue`). Used
    /// as a metadata sidecar for the live `/api/chat-adapters` feed, which
    /// carries status but not category or human-readable descriptions.
    static let byID: [String: ChannelCatalogEntry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.kindRawValue, $0) }
    )

    /// Look up the static metadata entry for a live adapter id.
    static func entry(id: String) -> ChannelCatalogEntry? { byID[id] }
}
