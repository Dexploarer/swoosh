// SwooshGateway/GatewayPlatform.swift — Multi-platform messaging gateway
//
// Hermes-inspired gateway: a single process that routes messages between
// the agent and multiple platforms (Telegram, Discord, Slack, etc.).

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gateway platform protocol
// ═══════════════════════════════════════════════════════════════════

/// A messaging platform adapter (Telegram, Discord, Slack, etc.).
public protocol GatewayPlatform: Sendable {
    var platformID: String { get }
    var displayName: String { get }
    var isConnected: Bool { get async }
    func start() async throws
    func stop() async throws
    func send(message: GatewayMessage, to channel: ChannelID) async throws
    func onMessage(_ handler: @escaping @Sendable (IncomingMessage) async -> Void)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Core types
// ═══════════════════════════════════════════════════════════════════

public typealias ChannelID = String

public struct GatewayMessage: Codable, Sendable {
    public let text: String
    public var attachments: [MessageAttachment]
    public var replyTo: String?
    public var metadata: [String: String]
    public init(text: String, attachments: [MessageAttachment] = [], replyTo: String? = nil, metadata: [String: String] = [:]) {
        self.text = text; self.attachments = attachments; self.replyTo = replyTo; self.metadata = metadata
    }
}

public struct MessageAttachment: Codable, Sendable {
    public let type: AttachmentType
    public let url: String?
    public let data: Data?
    public let filename: String?
    public enum AttachmentType: String, Codable, Sendable { case image, file, audio, video, code }
    public init(type: AttachmentType, url: String? = nil, data: Data? = nil, filename: String? = nil) {
        self.type = type; self.url = url; self.data = data; self.filename = filename
    }
}

public struct IncomingMessage: Sendable {
    public let platform: String
    public let channelID: ChannelID
    public let senderID: String
    public let senderName: String
    public let text: String
    public let attachments: [MessageAttachment]
    public let timestamp: Date
    public let rawPayload: [String: String]
    public init(platform: String, channelID: ChannelID, senderID: String, senderName: String,
                text: String, attachments: [MessageAttachment] = [], timestamp: Date = Date(), rawPayload: [String: String] = [:]) {
        self.platform = platform; self.channelID = channelID; self.senderID = senderID
        self.senderName = senderName; self.text = text; self.attachments = attachments
        self.timestamp = timestamp; self.rawPayload = rawPayload
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Channel directory
// ═══════════════════════════════════════════════════════════════════

/// Maps external platform users to Swoosh identities for cross-platform continuity.
public actor ChannelDirectory {
    private var channels: [ChannelID: ChannelInfo] = [:]

    public init() {}

    public struct ChannelInfo: Codable, Sendable {
        public let channelID: ChannelID
        public let platform: String
        public let userID: String
        public var displayName: String
        public var sessionID: String?
        public var lastMessageAt: Date
    }

    public func register(channelID: ChannelID, platform: String, userID: String, displayName: String) {
        channels[channelID] = ChannelInfo(channelID: channelID, platform: platform, userID: userID,
                                           displayName: displayName, lastMessageAt: Date())
    }

    public func lookup(_ channelID: ChannelID) -> ChannelInfo? { channels[channelID] }

    public func bindSession(_ channelID: ChannelID, sessionID: String) {
        channels[channelID]?.sessionID = sessionID
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gateway router
// ═══════════════════════════════════════════════════════════════════

/// Routes messages between platforms and the agent.
public actor GatewayRouter {
    private var platforms: [String: any GatewayPlatform] = [:]
    private var messageHandler: (@Sendable (IncomingMessage) async -> GatewayMessage?)?
    public let directory = ChannelDirectory()

    public init() {}

    public func register(platform: any GatewayPlatform) {
        platforms[platform.platformID] = platform
    }

    public func setHandler(_ handler: @escaping @Sendable (IncomingMessage) async -> GatewayMessage?) {
        messageHandler = handler
    }

    public func startAll() async throws {
        for (_, platform) in platforms {
            let handler = messageHandler
            let router = self
            platform.onMessage { message in
                if let response = await handler?(message) {
                    try? await platform.send(message: response, to: message.channelID)
                }
                await router.directory.register(channelID: message.channelID, platform: message.platform,
                                                  userID: message.senderID, displayName: message.senderName)
            }
            try await platform.start()
        }
    }

    public func stopAll() async throws {
        for (_, platform) in platforms { try await platform.stop() }
    }

    public func send(_ message: GatewayMessage, platform: String, channel: ChannelID) async throws {
        guard let p = platforms[platform] else { return }
        try await p.send(message: message, to: channel)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Webhook platform (generic)
// ═══════════════════════════════════════════════════════════════════

/// A generic webhook-based platform adapter.
public final class WebhookPlatform: GatewayPlatform, @unchecked Sendable {
    public let platformID: String
    public let displayName: String
    private var handler: (@Sendable (IncomingMessage) async -> Void)?
    private var _isConnected = false
    public var isConnected: Bool { _isConnected }

    public init(platformID: String = "webhook", displayName: String = "Webhook") {
        self.platformID = platformID; self.displayName = displayName
    }

    public func start() async throws { _isConnected = true }
    public func stop() async throws { _isConnected = false }
    public func send(message: GatewayMessage, to channel: ChannelID) async throws {}
    public func onMessage(_ handler: @escaping @Sendable (IncomingMessage) async -> Void) {
        self.handler = handler
    }

    /// Inject a message (called by HTTP endpoint handler).
    public func injectMessage(_ message: IncomingMessage) async {
        await handler?(message)
    }
}
