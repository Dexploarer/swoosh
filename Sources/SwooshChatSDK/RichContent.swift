// SwooshChatSDK/RichContent.swift — Markdown AST, cards, actions, and modals
import Foundation

public indirect enum MarkdownNode: Codable, Sendable, Hashable {
    case root([MarkdownNode])
    case paragraph([MarkdownNode])
    case text(String)
    case strong([MarkdownNode])
    case emphasis([MarkdownNode])
    case strikethrough([MarkdownNode])
    case inlineCode(String)
    case codeBlock(value: String, language: String?)
    case link(url: URL, children: [MarkdownNode], title: String?)
    case blockquote([MarkdownNode])

    public var markdown: String {
        switch self {
        case .root(let children):
            return children.map(\.markdown).joined(separator: "\n\n")
        case .paragraph(let children):
            return children.map(\.markdown).joined()
        case .text(let value):
            return value
        case .strong(let children):
            return "**\(children.map(\.markdown).joined())**"
        case .emphasis(let children):
            return "_\(children.map(\.markdown).joined())_"
        case .strikethrough(let children):
            return "~~\(children.map(\.markdown).joined())~~"
        case .inlineCode(let value):
            return "`\(value)`"
        case .codeBlock(let value, let language):
            return "```\(language ?? "")\n\(value)\n```"
        case .link(let url, let children, _):
            return "[\(children.map(\.markdown).joined())](\(url.absoluteString))"
        case .blockquote(let children):
            return children.map { "> \($0.markdown)" }.joined(separator: "\n")
        }
    }
}

public func root(_ children: [MarkdownNode]) -> MarkdownNode { .root(children) }
public func paragraph(_ children: [MarkdownNode]) -> MarkdownNode { .paragraph(children) }
public func text(_ value: String) -> MarkdownNode { .text(value) }
public func strong(_ children: [MarkdownNode]) -> MarkdownNode { .strong(children) }
public func emphasis(_ children: [MarkdownNode]) -> MarkdownNode { .emphasis(children) }
public func strikethrough(_ children: [MarkdownNode]) -> MarkdownNode { .strikethrough(children) }
public func inlineCode(_ value: String) -> MarkdownNode { .inlineCode(value) }
public func codeBlock(_ value: String, _ language: String? = nil) -> MarkdownNode { .codeBlock(value: value, language: language) }
public func link(_ url: URL, _ children: [MarkdownNode], title: String? = nil) -> MarkdownNode { .link(url: url, children: children, title: title) }
public func blockquote(_ children: [MarkdownNode]) -> MarkdownNode { .blockquote(children) }

public struct ChatCard: Codable, Sendable, Hashable {
    public let title: String?
    public let children: [ChatCardElement]

    public init(title: String? = nil, children: [ChatCardElement]) {
        self.title = title
        self.children = children
    }
}

public indirect enum ChatCardElement: Codable, Sendable, Hashable {
    case text(String)
    case markdown(String)
    case image(url: URL, alt: String?)
    case actions([ChatAction])
    case fields([ChatCardField])
    case section(title: String?, children: [ChatCardElement])
}

public struct ChatCardField: Codable, Sendable, Hashable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ChatAction: Codable, Sendable, Hashable {
    public enum Style: String, Codable, Sendable {
        case primary
        case secondary
        case danger
    }

    public let id: String
    public let label: String
    public let style: Style
    public let value: String?

    public init(id: String, label: String, style: Style = .secondary, value: String? = nil) {
        self.id = id
        self.label = label
        self.style = style
        self.value = value
    }
}

public struct ChatModal: Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let fields: [ChatModalField]
    public let submitLabel: String

    public init(id: String = UUID().uuidString, title: String, fields: [ChatModalField], submitLabel: String = "Submit") {
        self.id = id
        self.title = title
        self.fields = fields
        self.submitLabel = submitLabel
    }
}

public struct ChatModalField: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case text
        case multilineText
        case select
        case checkbox
    }

    public let id: String
    public let label: String
    public let kind: Kind
    public let required: Bool
    public let options: [String]

    public init(id: String, label: String, kind: Kind = .text, required: Bool = false, options: [String] = []) {
        self.id = id
        self.label = label
        self.kind = kind
        self.required = required
        self.options = options
    }
}
