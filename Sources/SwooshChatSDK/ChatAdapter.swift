// SwooshChatSDK/ChatAdapter.swift — Platform adapter protocol
import Foundation
import SwooshClient

public protocol ChatAdapter: Sendable {
    var id: String { get }
    var features: ChatAdapterFeatures { get }
    func post(threadID: ChatThreadID, message: ChatRichMessage) async throws -> SentChatMessage
    func postChannel(channelID: ChatChannelID, message: ChatRichMessage) async throws -> SentChatMessage
    func edit(messageID: String, threadID: ChatThreadID, message: ChatRichMessage) async throws
    func delete(messageID: String, threadID: ChatThreadID) async throws
    func addReaction(messageID: String, threadID: ChatThreadID, emoji: String) async throws
    func removeReaction(messageID: String, threadID: ChatThreadID, emoji: String) async throws
    func startTyping(threadID: ChatThreadID) async throws
    func fetchMessages(threadID: ChatThreadID, limit: Int?) async throws -> [ChatMessage]
    func fetchThread(threadID: ChatThreadID) async throws -> ChatThreadInfo
    func listThreads(channelID: ChatChannelID, limit: Int?) async throws -> [ChatThreadInfo]
    func channelInfo(channelID: ChatChannelID) async throws -> ChatChannelInfo
    func getUser(author: ChatAuthor) async throws -> ChatAuthor?
    func openDM(user: ChatAuthor) async throws -> ChatThreadID
}

public extension ChatAdapter {
    var features: ChatAdapterFeatures { ChatAdapterFeatures() }
    func edit(messageID: String, threadID: ChatThreadID, message: ChatRichMessage) async throws { throw ChatAdapterError.unsupported("edit") }
    func delete(messageID: String, threadID: ChatThreadID) async throws { throw ChatAdapterError.unsupported("delete") }
    func addReaction(messageID: String, threadID: ChatThreadID, emoji: String) async throws { throw ChatAdapterError.unsupported("addReaction") }
    func removeReaction(messageID: String, threadID: ChatThreadID, emoji: String) async throws { throw ChatAdapterError.unsupported("removeReaction") }
    func startTyping(threadID: ChatThreadID) async throws {}
    func fetchMessages(threadID: ChatThreadID, limit: Int?) async throws -> [ChatMessage] { [] }
    func fetchThread(threadID: ChatThreadID) async throws -> ChatThreadInfo { ChatThreadInfo(id: threadID, rootMessage: nil, replyCount: 0) }
    func listThreads(channelID: ChatChannelID, limit: Int?) async throws -> [ChatThreadInfo] { [] }
    func channelInfo(channelID: ChatChannelID) async throws -> ChatChannelInfo { ChatChannelInfo(id: channelID) }
    func getUser(author: ChatAuthor) async throws -> ChatAuthor? { author }
    func openDM(user: ChatAuthor) async throws -> ChatThreadID { throw ChatAdapterError.unsupported("openDM") }
}

public struct ChatAdapterFeatures: Codable, Sendable, Hashable {
    public var supportsEdit: Bool
    public var supportsDelete: Bool
    public var supportsReactions: Bool
    public var supportsTyping: Bool
    public var supportsStreaming: Bool
    public var supportsDMs: Bool
    public var supportsModals: Bool
    public var supportsCards: Bool

    public init(
        supportsEdit: Bool = false,
        supportsDelete: Bool = false,
        supportsReactions: Bool = false,
        supportsTyping: Bool = false,
        supportsStreaming: Bool = false,
        supportsDMs: Bool = false,
        supportsModals: Bool = false,
        supportsCards: Bool = true
    ) {
        self.supportsEdit = supportsEdit
        self.supportsDelete = supportsDelete
        self.supportsReactions = supportsReactions
        self.supportsTyping = supportsTyping
        self.supportsStreaming = supportsStreaming
        self.supportsDMs = supportsDMs
        self.supportsModals = supportsModals
        self.supportsCards = supportsCards
    }
}

public struct ChatThreadInfo: Codable, Sendable, Hashable {
    public let id: ChatThreadID
    public let rootMessage: ChatMessage?
    public let replyCount: Int

    public init(id: ChatThreadID, rootMessage: ChatMessage?, replyCount: Int) {
        self.id = id
        self.rootMessage = rootMessage
        self.replyCount = replyCount
    }
}

public enum ChatAdapterError: Error, Sendable, LocalizedError {
    case missingAdapter(String)
    case unsupported(String)
    case invalidThreadID(String)

    public var errorDescription: String? {
        switch self {
        case .missingAdapter(let id): "missing chat adapter: \(id)"
        case .unsupported(let op): "chat adapter does not support \(op)"
        case .invalidThreadID(let id): "invalid thread id: \(id)"
        }
    }
}

public actor MemoryChatAdapter: ChatAdapter {
    public let id: String
    public let features = ChatAdapterFeatures(
        supportsEdit: true,
        supportsDelete: true,
        supportsReactions: true,
        supportsTyping: true,
        supportsStreaming: true,
        supportsDMs: true,
        supportsModals: true,
        supportsCards: true
    )
    private let botAuthor: ChatAuthor
    private var messagesByThread: [ChatThreadID: [ChatMessage]] = [:]

    public init(id: String = "memory", botAuthor: ChatAuthor = ChatAuthor(userID: "swoosh", userName: "swoosh", isBot: true, isMe: true)) {
        self.id = id
        self.botAuthor = botAuthor
    }

    public func ingest(_ message: ChatMessage) {
        messagesByThread[message.threadID, default: []].append(message)
    }

    public func post(threadID: ChatThreadID, message: ChatRichMessage) async throws -> SentChatMessage {
        let text = render(message)
        let sent = SentChatMessage(threadID: threadID, text: text)
        messagesByThread[threadID, default: []].append(ChatMessage(id: sent.id, threadID: threadID, text: text, markdown: message.markdown, author: botAuthor))
        return sent
    }

    public func postChannel(channelID: ChatChannelID, message: ChatRichMessage) async throws -> SentChatMessage {
        let threadID = ChatThreadID("\(channelID.rawValue):\(UUID().uuidString)")
        return try await post(threadID: threadID, message: message)
    }

    public func edit(messageID: String, threadID: ChatThreadID, message: ChatRichMessage) async throws {
        guard var messages = messagesByThread[threadID], let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let old = messages[index]
        messages[index] = ChatMessage(
            id: old.id,
            threadID: old.threadID,
            text: render(message),
            markdown: message.markdown,
            author: old.author,
            metadata: ChatMessageMetadata(dateSent: old.metadata.dateSent, dateEdited: Date(), isEdited: true),
            attachments: old.attachments,
            isMention: old.isMention,
            subject: old.subject
        )
        messagesByThread[threadID] = messages
    }

    public func delete(messageID: String, threadID: ChatThreadID) async throws {
        messagesByThread[threadID]?.removeAll { $0.id == messageID }
    }

    public func addReaction(messageID: String, threadID: ChatThreadID, emoji: String) async throws {}
    public func removeReaction(messageID: String, threadID: ChatThreadID, emoji: String) async throws {}
    public func startTyping(threadID: ChatThreadID) async throws {}

    public func fetchMessages(threadID: ChatThreadID, limit: Int?) async throws -> [ChatMessage] {
        let messages = messagesByThread[threadID] ?? []
        if let limit { return Array(messages.suffix(limit)) }
        return messages
    }

    public func openDM(user: ChatAuthor) async throws -> ChatThreadID {
        ChatThreadID("\(id):dm-\(user.userID):\(UUID().uuidString)")
    }
}

public actor SwooshDaemonChatAdapter: ChatAdapter {
    public let id = "swoosh"
    public let features = ChatAdapterFeatures(supportsStreaming: true, supportsDMs: true)
    private let client: SwooshAPIClient
    private let botAuthor = ChatAuthor(userID: "swoosh", userName: "swoosh", isBot: true, isMe: true)

    public init(client: SwooshAPIClient) {
        self.client = client
    }

    public func post(threadID: ChatThreadID, message: ChatRichMessage) async throws -> SentChatMessage {
        let input = message.markdown ?? message.ast?.markdown ?? message.card?.plainText ?? ""
        let response = try await client.chat(ChatRequest(sessionID: threadID.rawValue, input: input))
        return SentChatMessage(threadID: threadID, text: response.message)
    }

    public func postChannel(channelID: ChatChannelID, message: ChatRichMessage) async throws -> SentChatMessage {
        let threadID = ChatThreadID("\(channelID.rawValue):default")
        return try await post(threadID: threadID, message: message)
    }

    public func fetchMessages(threadID: ChatThreadID, limit: Int?) async throws -> [ChatMessage] { [] }
    public func openDM(user: ChatAuthor) async throws -> ChatThreadID { ChatThreadID("swoosh:dm-\(user.userID):default") }
}

private func render(_ message: ChatRichMessage) -> String {
    if let markdown = message.markdown { return markdown }
    if let ast = message.ast { return ast.markdown }
    if let card = message.card { return card.plainText }
    return ""
}

private extension ChatCard {
    var plainText: String {
        ([title].compactMap(\.self) + children.map(\.plainText)).joined(separator: "\n")
    }
}

private extension ChatCardElement {
    var plainText: String {
        switch self {
        case .text(let text), .markdown(let text):
            return text
        case .image(_, let alt):
            return alt ?? ""
        case .actions(let actions):
            return actions.map { "[\($0.label)]" }.joined(separator: " ")
        case .fields(let fields):
            return fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        case .section(let title, let children):
            return ([title].compactMap(\.self) + children.map(\.plainText)).joined(separator: "\n")
        }
    }
}
