// SwooshUI/ContextMenus/SwooshContextMenus.swift
// Right-click context menus for all major interactive surfaces:
// - Chat messages
// - Board cards
// - Provider list items
// - Tool results / log entries
// - Memory vault entries
//
// Usage: attach .swooshChatContextMenu(message: m) to a message row.

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Chat message context menu

public struct ChatMessageContextMenu: ViewModifier {
    public struct Message: Identifiable {
        public let id: String
        public let role: String          // "user" | "assistant" | "tool"
        public let content: String
        public let hasToolResult: Bool
        public var isPinned: Bool

        public init(id: String = UUID().uuidString, role: String,
                    content: String, hasToolResult: Bool = false, isPinned: Bool = false) {
            self.id = id; self.role = role; self.content = content
            self.hasToolResult = hasToolResult; self.isPinned = isPinned
        }
    }

    let message: Message
    var onCopy:       (() -> Void)?
    var onEdit:       (() -> Void)?
    var onRerun:      (() -> Void)?
    var onPinMemory:  (() -> Void)?
    var onDelete:     (() -> Void)?
    var onViewTrace:  (() -> Void)?
    var onExportJSON: (() -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            Group {
                Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                #endif
                onCopy?()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if message.role == "user" {
                    Button { onEdit?() } label: {
                        Label("Edit Message", systemImage: "pencil")
                    }
                    Button { onRerun?() } label: {
                        Label("Re-run from Here", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            Divider()

            Group {
                Button { onPinMemory?() } label: {
                    Label(message.isPinned ? "Unpin from Memory" : "Pin to Memory",
                          systemImage: message.isPinned ? "pin.slash" : "pin")
                }

                if message.hasToolResult {
                    Button { onViewTrace?() } label: {
                        Label("View Tool Trace", systemImage: "list.bullet.rectangle")
                    }
                    Button { onExportJSON?() } label: {
                        Label("Export Tool Result as JSON", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Divider()

            Button(role: .destructive) { onDelete?() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Board card context menu

public struct BoardCardContextMenu: ViewModifier {
    public struct Card: Identifiable {
        public let id: String
        public let title: String
        public var lane: String
        public let availableLanes: [String]

        public init(id: String = UUID().uuidString, title: String,
                    lane: String, availableLanes: [String]) {
            self.id = id; self.title = title; self.lane = lane
            self.availableLanes = availableLanes
        }
    }

    let card: Card
    var onMoveLane:   ((String) -> Void)?
    var onDuplicate:  (() -> Void)?
    var onAssign:     (() -> Void)?
    var onArchive:    (() -> Void)?
    var onDelete:     (() -> Void)?
    var onCopyTitle:  (() -> Void)?
    var onViewDetail: (() -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            Button { onViewDetail?() } label: {
                Label("Open Card", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Divider()

            Menu("Move to Lane") {
                ForEach(card.availableLanes.filter { $0 != card.lane }, id: \.self) { lane in
                    Button(lane) { onMoveLane?(lane) }
                }
            }

            Button { onAssign?() } label: {
                Label("Assign Agent…", systemImage: "cpu")
            }

            Button { onDuplicate?() } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button { onCopyTitle?() } label: {
                Label("Copy Title", systemImage: "doc.on.doc")
            }

            Divider()

            Button { onArchive?() } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Button(role: .destructive) { onDelete?() } label: {
                Label("Delete Card", systemImage: "trash")
            }
        }
    }
}

// MARK: - Provider context menu

public struct ProviderContextMenu: ViewModifier {
    public struct Provider: Identifiable {
        public let id: String
        public let name: String
        public var isEnabled: Bool
        public var hasKey: Bool

        public init(id: String = UUID().uuidString, name: String,
                    isEnabled: Bool = true, hasKey: Bool = false) {
            self.id = id; self.name = name
            self.isEnabled = isEnabled; self.hasKey = hasKey
        }
    }

    let provider: Provider
    var onTest:        (() -> Void)?
    var onRefresh:     (() -> Void)?
    var onToggle:      (() -> Void)?
    var onViewKeys:    (() -> Void)?
    var onCopyID:      (() -> Void)?
    var onViewUsage:   (() -> Void)?
    var onRemove:      (() -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            Button { onTest?() } label: {
                Label("Test Connection", systemImage: "wifi")
            }
            Button { onRefresh?() } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
            }
            Button { onViewUsage?() } label: {
                Label("View Usage & Costs", systemImage: "chart.bar")
            }

            Divider()

            Button { onToggle?() } label: {
                Label(provider.isEnabled ? "Disable Provider" : "Enable Provider",
                      systemImage: provider.isEnabled ? "pause.circle" : "play.circle")
            }

            if provider.hasKey {
                Button { onViewKeys?() } label: {
                    Label("View API Key…", systemImage: "key.horizontal")
                }
            }

            Button { onCopyID?() } label: {
                Label("Copy Provider ID", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) { onRemove?() } label: {
                Label("Remove Provider", systemImage: "minus.circle")
            }
        }
    }
}

// MARK: - Tool result context menu

public struct ToolResultContextMenu: ViewModifier {
    public struct ToolResult: Identifiable {
        public let id: String
        public let toolName: String
        public let jsonPayload: String
        public let traceID: String?
        public let success: Bool

        public init(id: String = UUID().uuidString, toolName: String,
                    jsonPayload: String, traceID: String? = nil, success: Bool = true) {
            self.id = id; self.toolName = toolName
            self.jsonPayload = jsonPayload; self.traceID = traceID; self.success = success
        }
    }

    let result: ToolResult
    var onCopyJSON:    (() -> Void)?
    var onViewTrace:   (() -> Void)?
    var onRerun:       (() -> Void)?
    var onPinResult:   (() -> Void)?
    var onExport:      (() -> Void)?
    var onReport:      (() -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            Text(result.toolName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button { onCopyJSON?() } label: {
                Label("Copy JSON", systemImage: "curlybraces")
            }

            if result.traceID != nil {
                Button { onViewTrace?() } label: {
                    Label("View Trace", systemImage: "list.bullet.rectangle.fill")
                }
            }

            Button { onRerun?() } label: {
                Label("Re-run Tool", systemImage: "arrow.counterclockwise")
            }

            Button { onPinResult?() } label: {
                Label("Pin Result to Memory", systemImage: "pin")
            }

            Button { onExport?() } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }

            if !result.success {
                Divider()
                Button { onReport?() } label: {
                    Label("Report Error", systemImage: "exclamationmark.triangle")
                }
                .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Memory entry context menu

public struct MemoryContextMenu: ViewModifier {
    public struct MemoryEntry: Identifiable {
        public let id: String
        public let content: String
        public var isPinned: Bool
        public let createdAt: Date

        public init(id: String = UUID().uuidString, content: String,
                    isPinned: Bool = false, createdAt: Date = Date()) {
            self.id = id; self.content = content
            self.isPinned = isPinned; self.createdAt = createdAt
        }
    }

    let entry: MemoryEntry
    var onEdit:     (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onCopy:     (() -> Void)?
    var onExport:   (() -> Void)?
    var onDelete:   (() -> Void)?

    public func body(content: Content) -> some View {
        content.contextMenu {
            Button { onEdit?() } label: {
                Label("Edit Memory", systemImage: "pencil")
            }

            Button { onTogglePin?() } label: {
                Label(entry.isPinned ? "Unpin" : "Pin (Keep Forever)",
                      systemImage: entry.isPinned ? "pin.slash" : "pin.fill")
            }

            Button { onCopy?() } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            Button { onExport?() } label: {
                Label("Export as Markdown", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) { onDelete?() } label: {
                Label("Delete Memory", systemImage: "trash")
            }
        }
    }
}

// MARK: - Convenience View extensions

public extension View {
    func swooshChatContextMenu(
        message: ChatMessageContextMenu.Message,
        onCopy: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onRerun: (() -> Void)? = nil,
        onPinMemory: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onViewTrace: (() -> Void)? = nil,
        onExportJSON: (() -> Void)? = nil
    ) -> some View {
        modifier(ChatMessageContextMenu(
            message: message, onCopy: onCopy, onEdit: onEdit, onRerun: onRerun,
            onPinMemory: onPinMemory, onDelete: onDelete, onViewTrace: onViewTrace,
            onExportJSON: onExportJSON
        ))
    }

    func swooshBoardContextMenu(
        card: BoardCardContextMenu.Card,
        onMoveLane: ((String) -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onAssign: (() -> Void)? = nil,
        onArchive: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onViewDetail: (() -> Void)? = nil
    ) -> some View {
        modifier(BoardCardContextMenu(
            card: card, onMoveLane: onMoveLane, onDuplicate: onDuplicate,
            onAssign: onAssign, onArchive: onArchive, onDelete: onDelete,
            onViewDetail: onViewDetail
        ))
    }

    func swooshProviderContextMenu(
        provider: ProviderContextMenu.Provider,
        onTest: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        onToggle: (() -> Void)? = nil,
        onViewKeys: (() -> Void)? = nil,
        onViewUsage: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        modifier(ProviderContextMenu(
            provider: provider, onTest: onTest, onRefresh: onRefresh, onToggle: onToggle,
            onViewKeys: onViewKeys, onViewUsage: onViewUsage, onRemove: onRemove
        ))
    }

    func swooshToolResultContextMenu(
        result: ToolResultContextMenu.ToolResult,
        onCopyJSON: (() -> Void)? = nil,
        onViewTrace: (() -> Void)? = nil,
        onRerun: (() -> Void)? = nil,
        onPinResult: (() -> Void)? = nil
    ) -> some View {
        modifier(ToolResultContextMenu(
            result: result, onCopyJSON: onCopyJSON, onViewTrace: onViewTrace,
            onRerun: onRerun, onPinResult: onPinResult
        ))
    }

    func swooshMemoryContextMenu(
        entry: MemoryContextMenu.MemoryEntry,
        onEdit: (() -> Void)? = nil,
        onTogglePin: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(MemoryContextMenu(
            entry: entry, onEdit: onEdit, onTogglePin: onTogglePin,
            onCopy: onCopy, onDelete: onDelete
        ))
    }
}


