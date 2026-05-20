// SwooshChatSDK/Chat.swift — Unified Swift chat router
import Foundation

public typealias ChatMessageHandler = @Sendable (ChatThread, ChatMessage) async throws -> Void
public typealias ChatReactionHandler = @Sendable (ChatReactionEvent) async throws -> Void
public typealias ChatActionHandler = @Sendable (ChatActionEvent) async throws -> Void
public typealias ChatSlashCommandHandler = @Sendable (ChatSlashCommandEvent) async throws -> Void

public struct ChatConfiguration: Sendable {
    public let userName: String
    public let dedupeTTL: TimeInterval
    public let lockTTL: TimeInterval
    public let lockConflictPolicy: ChatLockConflictPolicy
    public let streamingUpdateInterval: TimeInterval
    public let fallbackStreamingPlaceholderText: String?

    public init(
        userName: String,
        dedupeTTL: TimeInterval = 300,
        lockTTL: TimeInterval = 600,
        lockConflictPolicy: ChatLockConflictPolicy = .drop,
        streamingUpdateInterval: TimeInterval = 0.5,
        fallbackStreamingPlaceholderText: String? = "..."
    ) {
        self.userName = userName
        self.dedupeTTL = dedupeTTL
        self.lockTTL = lockTTL
        self.lockConflictPolicy = lockConflictPolicy
        self.streamingUpdateInterval = streamingUpdateInterval
        self.fallbackStreamingPlaceholderText = fallbackStreamingPlaceholderText
    }
}

public actor Chat {
    public let configuration: ChatConfiguration
    public let state: any ChatStateAdapter
    private var adapters: [String: any ChatAdapter]
    private var mentionHandlers: [ChatMessageHandler] = []
    private var subscribedHandlers: [ChatMessageHandler] = []
    private var directMessageHandlers: [ChatMessageHandler] = []
    private var messageHandlers: [(ChatMessagePredicate, ChatMessageHandler)] = []
    private var reactionHandlers: [(Set<String>?, ChatReactionHandler)] = []
    private var actionHandlers: [String: ChatActionHandler] = [:]
    private var slashCommandHandlers: [String: ChatSlashCommandHandler] = [:]

    public init(
        configuration: ChatConfiguration,
        adapters: [String: any ChatAdapter],
        state: any ChatStateAdapter
    ) {
        self.configuration = configuration
        self.adapters = adapters
        self.state = state
    }

    public func registerAdapter(_ adapter: any ChatAdapter) {
        adapters[adapter.id] = adapter
    }

    public func getAdapter(_ id: String) throws -> any ChatAdapter {
        guard let adapter = adapters[id] else { throw ChatAdapterError.missingAdapter(id) }
        return adapter
    }

    public func thread(_ id: ChatThreadID) -> ChatThread {
        ChatThread(id: id, chat: self)
    }

    public func channel(_ id: ChatChannelID) -> ChatChannel {
        ChatChannel(id: id, chat: self)
    }

    public func openDM(_ user: ChatAuthor, adapterID: String? = nil) async throws -> ChatThread {
        let adapter = try adapterFor(adapterID: adapterID ?? adapters.keys.sorted().first)
        let id = try await adapter.openDM(user: user)
        return thread(id)
    }

    public func onNewMention(_ handler: @escaping ChatMessageHandler) {
        mentionHandlers.append(handler)
    }

    public func onSubscribedMessage(_ handler: @escaping ChatMessageHandler) {
        subscribedHandlers.append(handler)
    }

    public func onDirectMessage(_ handler: @escaping ChatMessageHandler) {
        directMessageHandlers.append(handler)
    }

    public func onNewMessage(containing keyword: String, _ handler: @escaping ChatMessageHandler) {
        messageHandlers.append((ChatMessagePredicate { $0.text.localizedCaseInsensitiveContains(keyword) }, handler))
    }

    public func onNewMessage(_ predicate: ChatMessagePredicate, _ handler: @escaping ChatMessageHandler) {
        messageHandlers.append((predicate, handler))
    }

    public func onReaction(_ emoji: [String]? = nil, _ handler: @escaping ChatReactionHandler) {
        reactionHandlers.append((emoji.map(Set.init), handler))
    }

    public func onAction(id: String, _ handler: @escaping ChatActionHandler) {
        actionHandlers[id] = handler
    }

    public func onSlashCommand(_ command: String, _ handler: @escaping ChatSlashCommandHandler) {
        slashCommandHandlers[command] = handler
    }

    public func handle(_ message: ChatMessage) async throws {
        if try await state.hasSeenMessage(id: message.id) { return }
        try await state.markMessageSeen(id: message.id, ttl: configuration.dedupeTTL)
        let force = configuration.lockConflictPolicy == .force
        let lock = try await state.acquireLock(threadID: message.threadID, ttl: configuration.lockTTL, force: force)
        guard lock == .acquired else { return }

        do {
            let wasSubscribed = try await state.isSubscribed(threadID: message.threadID)
            let thread = self.thread(message.threadID)
            if message.isMention {
                for handler in mentionHandlers { try await handler(thread, message) }
            }
            if wasSubscribed {
                for handler in subscribedHandlers { try await handler(thread, message) }
            }
            if message.threadID.rawValue.contains(":dm-") {
                for handler in directMessageHandlers { try await handler(thread, message) }
            }
            for (predicate, handler) in messageHandlers where predicate.matches(message) {
                try await handler(thread, message)
            }
            try await state.releaseLock(threadID: message.threadID)
        } catch {
            try? await state.releaseLock(threadID: message.threadID)
            throw error
        }
    }

    public func handle(_ event: ChatReactionEvent) async throws {
        for (filter, handler) in reactionHandlers where filter == nil || filter?.contains(event.emoji) == true {
            try await handler(event)
        }
    }

    public func handle(_ event: ChatActionEvent) async throws {
        try await actionHandlers[event.actionID]?(event)
    }

    public func handle(_ event: ChatSlashCommandEvent) async throws {
        try await slashCommandHandlers[event.command]?(event)
    }

    func adapterFor(threadID: ChatThreadID) throws -> any ChatAdapter {
        guard let adapterID = threadID.adapterID else { throw ChatAdapterError.invalidThreadID(threadID.rawValue) }
        return try getAdapter(adapterID)
    }

    func adapterFor(channelID: ChatChannelID) throws -> any ChatAdapter {
        guard let adapterID = channelID.adapterID else { throw ChatAdapterError.invalidThreadID(channelID.rawValue) }
        return try getAdapter(adapterID)
    }

    private func adapterFor(adapterID: String?) throws -> any ChatAdapter {
        guard let adapterID else { throw ChatAdapterError.missingAdapter("default") }
        return try getAdapter(adapterID)
    }
}

public struct ChatMessagePredicate: Sendable {
    private let closure: @Sendable (ChatMessage) -> Bool

    public init(_ closure: @escaping @Sendable (ChatMessage) -> Bool) {
        self.closure = closure
    }

    public func matches(_ message: ChatMessage) -> Bool {
        closure(message)
    }
}

public struct ChatThread: Sendable {
    public let id: ChatThreadID
    private let chat: Chat

    public init(id: ChatThreadID, chat: Chat) {
        self.id = id
        self.chat = chat
    }

    public var channel: ChatChannel {
        ChatChannel(id: id.channelID ?? ChatChannelID(id.rawValue), chat: chat)
    }

    public func post(_ message: PostableMessage) async throws -> SentChatMessage {
        let adapter = try await chat.adapterFor(threadID: id)
        switch message {
        case .text(let text):
            return try await adapter.post(threadID: id, message: ChatRichMessage(markdown: text))
        case .markdown(let text):
            return try await adapter.post(threadID: id, message: ChatRichMessage(markdown: text))
        case .rich(let rich):
            return try await adapter.post(threadID: id, message: rich)
        case .stream(let stream):
            return try await postStream(StreamingPlan(stream: stream))
        case .streamingPlan(let plan):
            return try await postStream(plan)
        }
    }

    public func post(_ text: String) async throws -> SentChatMessage {
        try await post(.text(text))
    }

    public func subscribe() async throws {
        try await chat.state.subscribe(threadID: id)
    }

    public func unsubscribe() async throws {
        try await chat.state.unsubscribe(threadID: id)
    }

    public func isSubscribed() async throws -> Bool {
        try await chat.state.isSubscribed(threadID: id)
    }

    public func setState<T: Encodable & Sendable>(_ value: T, replace: Bool = true, ttl: TimeInterval? = 30 * 24 * 60 * 60) async throws {
        try await chat.state.setThreadState(value, threadID: id, replace: replace, ttl: ttl)
    }

    public func state<T: Decodable & Sendable>(_ type: T.Type) async throws -> T? {
        try await chat.state.getThreadState(type, threadID: id)
    }

    public func startTyping() async throws {
        try await chat.adapterFor(threadID: id).startTyping(threadID: id)
    }

    public func messages(limit: Int? = nil) async throws -> [ChatMessage] {
        try await chat.adapterFor(threadID: id).fetchMessages(threadID: id, limit: limit)
    }

    public func getParticipants() async throws -> [ChatAuthor] {
        var seen: Set<String> = []
        var authors: [ChatAuthor] = []
        for message in try await messages() where message.author.isBot != true && !seen.contains(message.author.userID) {
            seen.insert(message.author.userID)
            authors.append(message.author)
        }
        return authors
    }

    private func postStream(_ plan: StreamingPlan) async throws -> SentChatMessage {
        let adapter = try await chat.adapterFor(threadID: id)
        var accumulated = ""
        var sent: SentChatMessage?
        if let placeholder = plan.placeholder {
            sent = try await adapter.post(threadID: id, message: ChatRichMessage(markdown: placeholder))
        }
        var lastUpdate = Date.distantPast
        for try await chunk in plan.stream {
            accumulated += chunk.textValue
            if sent == nil {
                sent = try await adapter.post(threadID: id, message: ChatRichMessage(markdown: accumulated))
                lastUpdate = Date()
                continue
            }
            if Date().timeIntervalSince(lastUpdate) >= plan.updateInterval, let sent {
                try? await adapter.edit(messageID: sent.id, threadID: id, message: ChatRichMessage(markdown: healedMarkdown(accumulated)))
                lastUpdate = Date()
            }
        }
        if let sent {
            try? await adapter.edit(messageID: sent.id, threadID: id, message: ChatRichMessage(markdown: accumulated))
            return SentChatMessage(id: sent.id, threadID: id, text: accumulated)
        }
        return try await adapter.post(threadID: id, message: ChatRichMessage(markdown: accumulated))
    }
}

public struct ChatChannel: Sendable {
    public let id: ChatChannelID
    private let chat: Chat

    public init(id: ChatChannelID, chat: Chat) {
        self.id = id
        self.chat = chat
    }

    public func post(_ message: PostableMessage) async throws -> SentChatMessage {
        let adapter = try await chat.adapterFor(channelID: id)
        switch message {
        case .text(let text), .markdown(let text):
            return try await adapter.postChannel(channelID: id, message: ChatRichMessage(markdown: text))
        case .rich(let rich):
            return try await adapter.postChannel(channelID: id, message: rich)
        case .stream, .streamingPlan:
            let thread = ChatThread(id: ChatThreadID("\(id.rawValue):\(UUID().uuidString)"), chat: chat)
            return try await thread.post(message)
        }
    }

    public func threads(limit: Int? = nil) async throws -> [ChatThreadInfo] {
        try await chat.adapterFor(channelID: id).listThreads(channelID: id, limit: limit)
    }

    public func fetchMetadata() async throws -> ChatChannelInfo {
        try await chat.adapterFor(channelID: id).channelInfo(channelID: id)
    }
}

public struct ChatReactionEvent: Sendable {
    public let emoji: String
    public let rawEmoji: String
    public let added: Bool
    public let user: ChatAuthor
    public let message: ChatMessage?
    public let thread: ChatThread
    public let messageID: String
    public let threadID: ChatThreadID
    public let adapterID: String

    public init(emoji: String, rawEmoji: String? = nil, added: Bool = true, user: ChatAuthor, message: ChatMessage? = nil, thread: ChatThread, messageID: String, adapterID: String) {
        self.emoji = emoji
        self.rawEmoji = rawEmoji ?? emoji
        self.added = added
        self.user = user
        self.message = message
        self.thread = thread
        self.messageID = messageID
        self.threadID = thread.id
        self.adapterID = adapterID
    }
}

public struct ChatActionEvent: Sendable {
    public let actionID: String
    public let value: String?
    public let thread: ChatThread
    public let user: ChatAuthor

    public init(actionID: String, value: String? = nil, thread: ChatThread, user: ChatAuthor) {
        self.actionID = actionID
        self.value = value
        self.thread = thread
        self.user = user
    }
}

public struct ChatSlashCommandEvent: Sendable {
    public let command: String
    public let arguments: String
    public let thread: ChatThread
    public let user: ChatAuthor

    public init(command: String, arguments: String, thread: ChatThread, user: ChatAuthor) {
        self.command = command
        self.arguments = arguments
        self.thread = thread
        self.user = user
    }
}

private func healedMarkdown(_ text: String) -> String {
    var value = text
    if value.filter({ $0 == "`" }).count % 2 == 1 { value.append("`") }
    if value.components(separatedBy: "**").count % 2 == 0 { value.append("**") }
    if value.hasSuffix("|") { value.append(" ") }
    return value
}
