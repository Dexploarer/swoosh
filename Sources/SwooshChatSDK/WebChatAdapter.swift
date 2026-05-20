// SwooshChatSDK/WebChatAdapter.swift — Local browser chat adapter
import Foundation

public actor WebChatAdapter: ChatAdapter {
    public let id = "web"
    public let features = ChatAdapterFeatures(
        supportsEdit: true,
        supportsTyping: true,
        supportsStreaming: true,
        supportsCards: false
    )
    private let storage = MemoryChatAdapter(id: "web")

    public init() {}

    public func post(threadID: ChatThreadID, message: ChatRichMessage) async throws -> SentChatMessage {
        try await storage.post(threadID: threadID, message: message)
    }

    public func postChannel(channelID: ChatChannelID, message: ChatRichMessage) async throws -> SentChatMessage {
        try await storage.postChannel(channelID: channelID, message: message)
    }

    public func edit(messageID: String, threadID: ChatThreadID, message: ChatRichMessage) async throws {
        try await storage.edit(messageID: messageID, threadID: threadID, message: message)
    }

    public func fetchMessages(threadID: ChatThreadID, limit: Int?) async throws -> [ChatMessage] {
        try await storage.fetchMessages(threadID: threadID, limit: limit)
    }
}
