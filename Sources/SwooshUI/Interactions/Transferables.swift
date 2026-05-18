// SwooshUI/Interactions/Transferables.swift — Drag-drop payloads (0.4A)
//
// Lightweight `Transferable` payloads for the dashboard's draggable
// surfaces. Each type carries its own `id` + minimal context so a drop
// destination can resolve the full object out of its store.
//
// Drag semantics:
//   - Memory entry → drop on chat composer = inject as context; drop on
//     trash = delete; drop on another memory category = re-tag.
//   - Board card → drop on a lane = move; drop on agent = assign.
//   - Scout record → drop on memory section = propose as candidate.

import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Memory drag payload

public struct SwooshMemoryDrag: Codable, Sendable, Transferable {
    public let id: String
    public let text: String
    public let category: String

    public init(id: String, text: String, category: String) {
        self.id = id
        self.text = text
        self.category = category
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swooshMemory)
        ProxyRepresentation(exporting: \.text)
    }
}

// MARK: - Board card drag payload

public struct SwooshBoardCardDrag: Codable, Sendable, Transferable {
    public let id: String
    public let title: String
    public let lane: String

    public init(id: String, title: String, lane: String) {
        self.id = id
        self.title = title
        self.lane = lane
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swooshBoardCard)
        ProxyRepresentation(exporting: \.title)
    }
}

// MARK: - Scout record drag payload

public struct SwooshScoutDrag: Codable, Sendable, Transferable {
    public let id: String
    public let source: String
    public let snippet: String

    public init(id: String, source: String, snippet: String) {
        self.id = id
        self.source = source
        self.snippet = snippet
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swooshScoutRecord)
        ProxyRepresentation(exporting: \.snippet)
    }
}

// MARK: - Agent reference drag

public struct SwooshAgentDrag: Codable, Sendable, Transferable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .swooshAgent)
        ProxyRepresentation(exporting: \.name)
    }
}

// MARK: - UT types

public extension UTType {
    static let swooshMemory      = UTType(exportedAs: "ai.swoosh.memory")
    static let swooshBoardCard   = UTType(exportedAs: "ai.swoosh.board.card")
    static let swooshScoutRecord = UTType(exportedAs: "ai.swoosh.scout.record")
    static let swooshAgent       = UTType(exportedAs: "ai.swoosh.agent")
}

// MARK: - Generic drop destination helpers

public struct SwooshDropTarget<Payload: Transferable & Codable & Sendable>: ViewModifier {
    let payloadType: Payload.Type
    let isTargetedBinding: Binding<Bool>?
    let onDrop: ([Payload]) -> Bool

    public init(
        _ type: Payload.Type,
        isTargeted: Binding<Bool>? = nil,
        onDrop: @escaping ([Payload]) -> Bool
    ) {
        self.payloadType = type
        self.isTargetedBinding = isTargeted
        self.onDrop = onDrop
    }

    public func body(content: Content) -> some View {
        content.dropDestination(for: Payload.self) { items, _ in
            onDrop(items)
        } isTargeted: { hovering in
            isTargetedBinding?.wrappedValue = hovering
        }
    }
}

public extension View {
    /// One-liner drop destination for a Swoosh `Transferable` payload.
    /// Returns true from `onDrop` to indicate "drop accepted."
    func swooshDropDestination<P: Transferable & Codable & Sendable>(
        _ type: P.Type,
        isTargeted: Binding<Bool>? = nil,
        onDrop: @escaping ([P]) -> Bool
    ) -> some View {
        modifier(SwooshDropTarget(type, isTargeted: isTargeted, onDrop: onDrop))
    }
}
