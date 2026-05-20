// SwooshChatSDK/ChatAI.swift — AI conversion and agent-facing chat tools
import Foundation
import SwooshClient

public struct ToAiMessagesOptions: Sendable {
    public let includeNames: Bool
    public let transformMessage: (@Sendable (AiChatMessage, ChatMessage) async -> AiChatMessage?)?
    public let onUnsupportedAttachment: (@Sendable (ChatAttachment, ChatMessage) async -> Void)?

    public init(
        includeNames: Bool = false,
        transformMessage: (@Sendable (AiChatMessage, ChatMessage) async -> AiChatMessage?)? = nil,
        onUnsupportedAttachment: (@Sendable (ChatAttachment, ChatMessage) async -> Void)? = nil
    ) {
        self.includeNames = includeNames
        self.transformMessage = transformMessage
        self.onUnsupportedAttachment = onUnsupportedAttachment
    }
}

public func toAiMessages(_ messages: [ChatMessage], options: ToAiMessagesOptions = ToAiMessagesOptions()) async -> [AiChatMessage] {
    var output: [AiChatMessage] = []
    for message in messages.sorted(by: { $0.metadata.dateSent < $1.metadata.dateSent }) {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !message.attachments.isEmpty else { continue }
        let role: AiChatMessage.Role = message.author.isMe ? .assistant : .user
        let prefix = options.includeNames && role == .user ? "[\(message.author.userName)]: " : ""
        let content = await contentFor(message: message, prefix: prefix, options: options)
        var ai = AiChatMessage(role: role, content: content)
        if let transform = options.transformMessage {
            guard let transformed = await transform(ai, message) else { continue }
            ai = transformed
        }
        output.append(ai)
    }
    return output
}

private func contentFor(message: ChatMessage, prefix: String, options: ToAiMessagesOptions) async -> AiChatMessageContent {
    guard !message.attachments.isEmpty else {
        return .text(prefix + message.text)
    }
    var parts: [AiChatMessagePart] = [.text(prefix + message.text)]
    for attachment in message.attachments {
        if attachment.mediaType.hasPrefix("image/") {
            parts.append(.image(data: attachment.data, url: attachment.url, mediaType: attachment.mediaType))
        } else if isTextLike(attachment.mediaType) {
            parts.append(.file(data: attachment.data, url: attachment.url, filename: attachment.filename, mediaType: attachment.mediaType))
        } else {
            await options.onUnsupportedAttachment?(attachment, message)
        }
    }
    return .parts(parts)
}

private func isTextLike(_ mediaType: String) -> Bool {
    mediaType.hasPrefix("text/") ||
        ["application/json", "application/xml", "application/javascript", "application/typescript", "application/yaml", "application/toml"].contains(mediaType)
}

public enum ChatToolPreset: String, Codable, Sendable {
    case reader
    case messenger
    case moderator
}

public struct ChatToolPolicy: Sendable {
    public let requireApprovalForWrites: Bool
    public let presets: Set<ChatToolPreset>

    public init(requireApprovalForWrites: Bool = true, presets: Set<ChatToolPreset> = [.moderator]) {
        self.requireApprovalForWrites = requireApprovalForWrites
        self.presets = presets
    }
}

public struct ChatToolBinding: Sendable {
    public let chat: Chat
    public let policy: ChatToolPolicy

    public init(chat: Chat, policy: ChatToolPolicy = ChatToolPolicy()) {
        self.chat = chat
        self.policy = policy
    }

    public func fetchMessages(threadID: ChatThreadID, limit: Int? = nil) async throws -> [ChatMessage] {
        try require(.reader)
        return try await chat.thread(threadID).messages(limit: limit)
    }

    public func postMessage(threadID: ChatThreadID, markdown: String) async throws -> SentChatMessage {
        try require(.messenger)
        return try await chat.thread(threadID).post(.markdown(markdown))
    }

    public func postChannelMessage(channelID: ChatChannelID, markdown: String) async throws -> SentChatMessage {
        try require(.messenger)
        return try await chat.channel(channelID).post(.markdown(markdown))
    }

    public func sendDirectMessage(user: ChatAuthor, adapterID: String, markdown: String) async throws -> SentChatMessage {
        try require(.messenger)
        let thread = try await chat.openDM(user, adapterID: adapterID)
        return try await thread.post(.markdown(markdown))
    }

    public func subscribeThread(threadID: ChatThreadID) async throws {
        try require(.moderator)
        try await chat.thread(threadID).subscribe()
    }

    public func unsubscribeThread(threadID: ChatThreadID) async throws {
        try require(.moderator)
        try await chat.thread(threadID).unsubscribe()
    }

    private func require(_ preset: ChatToolPreset) throws {
        guard policy.presets.contains(.moderator) || policy.presets.contains(preset) else {
            throw ChatAIToolError.presetDisabled(preset.rawValue)
        }
    }
}

public enum ChatAIToolError: Error, Sendable, LocalizedError {
    case presetDisabled(String)

    public var errorDescription: String? {
        switch self {
        case .presetDisabled(let preset): "chat tool preset is disabled: \(preset)"
        }
    }
}
