// SwooshChatSDK/ChatTypes.swift — Swift-native chat platform model
import Foundation
import SwooshClient

public struct ChatID: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public struct ChatThreadID: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var adapterID: String? { rawValue.split(separator: ":", maxSplits: 1).first.map(String.init) }
    public var channelID: ChatChannelID? {
        let parts = rawValue.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        return ChatChannelID("\(parts[0]):\(parts[1])")
    }
}

public struct ChatChannelID: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var adapterID: String? { rawValue.split(separator: ":", maxSplits: 1).first.map(String.init) }
}

public struct ChatAuthor: Codable, Sendable, Hashable {
    public let userID: String
    public let userName: String
    public let fullName: String
    public let isBot: Bool?
    public let isMe: Bool
    public let email: String?
    public let avatarURL: URL?

    public init(userID: String, userName: String, fullName: String? = nil, isBot: Bool? = nil, isMe: Bool = false, email: String? = nil, avatarURL: URL? = nil) {
        self.userID = userID
        self.userName = userName
        self.fullName = fullName ?? userName
        self.isBot = isBot
        self.isMe = isMe
        self.email = email
        self.avatarURL = avatarURL
    }
}

public struct ChatAttachment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let filename: String
    public let mediaType: String
    public let url: URL?
    public let data: Data?

    public init(id: String = UUID().uuidString, filename: String, mediaType: String, url: URL? = nil, data: Data? = nil) {
        self.id = id
        self.filename = filename
        self.mediaType = mediaType
        self.url = url
        self.data = data
    }
}

public struct ChatMessageMetadata: Codable, Sendable, Hashable {
    public let dateSent: Date
    public let dateEdited: Date?
    public let isEdited: Bool

    public init(dateSent: Date = Date(), dateEdited: Date? = nil, isEdited: Bool = false) {
        self.dateSent = dateSent
        self.dateEdited = dateEdited
        self.isEdited = isEdited
    }
}

public struct ChatMessage: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let threadID: ChatThreadID
    public let text: String
    public let markdown: String?
    public let author: ChatAuthor
    public let metadata: ChatMessageMetadata
    public let attachments: [ChatAttachment]
    public let isMention: Bool
    public let subject: String?

    public init(
        id: String = UUID().uuidString,
        threadID: ChatThreadID,
        text: String,
        markdown: String? = nil,
        author: ChatAuthor,
        metadata: ChatMessageMetadata = ChatMessageMetadata(),
        attachments: [ChatAttachment] = [],
        isMention: Bool = false,
        subject: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.text = text
        self.markdown = markdown
        self.author = author
        self.metadata = metadata
        self.attachments = attachments
        self.isMention = isMention
        self.subject = subject
    }
}

public struct ChatChannelInfo: Codable, Sendable, Hashable {
    public let id: ChatChannelID
    public let name: String?
    public let memberCount: Int?

    public init(id: ChatChannelID, name: String? = nil, memberCount: Int? = nil) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
    }
}

public struct SentChatMessage: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let threadID: ChatThreadID
    public let text: String

    public init(id: String = UUID().uuidString, threadID: ChatThreadID, text: String) {
        self.id = id
        self.threadID = threadID
        self.text = text
    }
}

public struct ChatTaskUpdate: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable {
        case pending
        case inProgress
        case complete
        case error
    }

    public let id: String
    public let title: String
    public let status: Status
    public let details: String?
    public let output: String?

    public init(id: String, title: String, status: Status, details: String? = nil, output: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.details = details
        self.output = output
    }
}

public enum ChatStreamChunk: Codable, Sendable, Hashable {
    case markdownText(String)
    case taskUpdate(ChatTaskUpdate)
    case planUpdate(title: String)

    public var textValue: String {
        switch self {
        case .markdownText(let text):
            return text
        case .taskUpdate(let task):
            return [task.title, task.output].compactMap(\.self).joined(separator: ": ")
        case .planUpdate(let title):
            return title
        }
    }
}

public struct StreamingPlan: Sendable {
    public let stream: AsyncThrowingStream<ChatStreamChunk, Error>
    public let updateInterval: TimeInterval
    public let placeholder: String?

    public init(stream: AsyncThrowingStream<ChatStreamChunk, Error>, updateInterval: TimeInterval = 0.5, placeholder: String? = "...") {
        self.stream = stream
        self.updateInterval = updateInterval
        self.placeholder = placeholder
    }
}

public enum PostableMessage: Sendable {
    case text(String)
    case markdown(String)
    case rich(ChatRichMessage)
    case stream(AsyncThrowingStream<ChatStreamChunk, Error>)
    case streamingPlan(StreamingPlan)
}

public struct ChatRichMessage: Codable, Sendable, Hashable {
    public let markdown: String?
    public let ast: MarkdownNode?
    public let card: ChatCard?
    public let attachments: [ChatAttachment]

    public init(markdown: String? = nil, ast: MarkdownNode? = nil, card: ChatCard? = nil, attachments: [ChatAttachment] = []) {
        self.markdown = markdown
        self.ast = ast
        self.card = card
        self.attachments = attachments
    }
}

extension PostableMessage: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .text(value)
    }
}

public enum AiChatMessageContent: Codable, Sendable, Hashable {
    case text(String)
    case parts([AiChatMessagePart])
}

public enum AiChatMessagePart: Codable, Sendable, Hashable {
    case text(String)
    case image(data: Data?, url: URL?, mediaType: String?)
    case file(data: Data?, url: URL?, filename: String?, mediaType: String)
}

public struct AiChatMessage: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let content: AiChatMessageContent

    public init(role: Role, content: AiChatMessageContent) {
        self.role = role
        self.content = content
    }
}
