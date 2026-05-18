// SwooshUI/Spotlight/SpotlightIndexer.swift — CoreSpotlight bridge (0.4A)
//
// Indexes approved memories and session titles so the user can find them
// with Cmd-Space (macOS) or the unified search bar (iOS). Items dispatch
// into Swoosh via universal links: `swoosh://memory/{id}` or
// `swoosh://session/{id}`. The host installs the URL handler.
//
// All Spotlight work happens off the main actor — the public API is async.

import Foundation
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

// MARK: - Indexable items (UI-side; not the canonical domain shape)

public struct SwooshSpotlightMemory: Sendable {
    public let id: String
    public let text: String
    public let category: String

    public init(id: String, text: String, category: String) {
        self.id = id
        self.text = text
        self.category = category
    }
}

public struct SwooshSpotlightSession: Sendable {
    public let id: String
    public let title: String
    public let preview: String
    public let updatedAt: Date

    public init(id: String, title: String, preview: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
    }
}

// MARK: - Indexer

public actor SwooshSpotlightIndexer {

    public static let shared = SwooshSpotlightIndexer()

    private let domainID: String

    public init(domainID: String = "ai.swoosh.spotlight") {
        self.domainID = domainID
    }

    /// Replace the indexed memory set. Pass the full current set — items
    /// missing from the array are removed from Spotlight.
    public func indexMemories(_ memories: [SwooshSpotlightMemory]) async throws {
        #if canImport(CoreSpotlight)
        let items: [CSSearchableItem] = memories.map { memory in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = memory.text
            attrs.contentDescription = "Memory · \(memory.category)"
            attrs.keywords = ["swoosh", "memory", memory.category]
            attrs.identifier = memory.id
            attrs.contentURL = URL(string: "swoosh://memory/\(memory.id)")
            let item = CSSearchableItem(
                uniqueIdentifier: memory.id,
                domainIdentifier: "\(domainID).memories",
                attributeSet: attrs
            )
            return item
        }
        try await indexItems(items, domain: "\(domainID).memories")
        #endif
    }

    /// Replace the indexed session set.
    public func indexSessions(_ sessions: [SwooshSpotlightSession]) async throws {
        #if canImport(CoreSpotlight)
        let items: [CSSearchableItem] = sessions.map { session in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = session.title
            attrs.contentDescription = session.preview
            attrs.contentModificationDate = session.updatedAt
            attrs.keywords = ["swoosh", "chat", "session"]
            attrs.identifier = session.id
            attrs.contentURL = URL(string: "swoosh://session/\(session.id)")
            let item = CSSearchableItem(
                uniqueIdentifier: session.id,
                domainIdentifier: "\(domainID).sessions",
                attributeSet: attrs
            )
            return item
        }
        try await indexItems(items, domain: "\(domainID).sessions")
        #endif
    }

    /// Clear every Swoosh-indexed item — useful on sign-out or reset.
    public func clearAll() async throws {
        #if canImport(CoreSpotlight)
        try await CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [
                "\(domainID).memories",
                "\(domainID).sessions",
            ])
        #endif
    }

    // MARK: - Private

    #if canImport(CoreSpotlight)
    private func indexItems(_ items: [CSSearchableItem], domain: String) async throws {
        let index = CSSearchableIndex.default()
        // Clear-then-index keeps the Spotlight set in sync with the caller's
        // current array without diffing.
        try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        try await index.indexSearchableItems(items)
    }
    #endif
}

// MARK: - URL routing

public enum SwooshSpotlightURL {
    /// Parse a `swoosh://...` URL produced by a Spotlight hit. Returns nil
    /// if the URL isn't a recognised Swoosh deep-link.
    public static func parse(_ url: URL) -> SwooshSpotlightDestination? {
        guard url.scheme == "swoosh" else { return nil }
        let host = url.host ?? ""
        let id = url.pathComponents.dropFirst().joined(separator: "/")
        switch host {
        case "memory":  return .memory(id: id)
        case "session": return .session(id: id)
        default:        return nil
        }
    }
}

public enum SwooshSpotlightDestination: Sendable, Equatable {
    case memory(id: String)
    case session(id: String)
}
