// SwooshUI/Toolbar/SwooshToolbarConfig.swift
// User-customizable app window toolbar system.
// Mirrors NSToolbar concepts but fully SwiftUI-native with drag-to-reorder,
// per-item visibility toggles, and JSON persistence.

import SwiftUI
import Foundation

// MARK: - Toolbar item definitions

/// Every item that can live in the main window toolbar.
public enum SwooshToolbarItem: String, Codable, Sendable, CaseIterable, Identifiable {
    case newChat
    case runWorkflow
    case board
    case approvals
    case agentStatus
    case providers
    case modelSelector
    case search
    case memoryVault
    case toolLog
    case settings
    case spacer           // flexible spacer
    case divider          // visual separator

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .newChat:       return "New Chat"
        case .runWorkflow:   return "Run Workflow"
        case .board:         return "Board"
        case .approvals:     return "Approvals"
        case .agentStatus:   return "Agent Status"
        case .providers:     return "Providers"
        case .modelSelector: return "Model"
        case .search:        return "Search"
        case .memoryVault:   return "Memory"
        case .toolLog:       return "Tool Log"
        case .settings:      return "Settings"
        case .spacer:        return "Flexible Space"
        case .divider:       return "Separator"
        }
    }

    public var icon: String {
        switch self {
        case .newChat:       return "bubble.left.and.bubble.right.fill"
        case .runWorkflow:   return "play.circle.fill"
        case .board:         return "rectangle.3.group.fill"
        case .approvals:     return "checkmark.seal.fill"
        case .agentStatus:   return "cpu.fill"
        case .providers:     return "cloud.fill"
        case .modelSelector: return "brain"
        case .search:        return "magnifyingglass"
        case .memoryVault:   return "archivebox.fill"
        case .toolLog:       return "list.bullet.rectangle.fill"
        case .settings:      return "gearshape.fill"
        case .spacer:        return "arrow.left.and.right"
        case .divider:       return "minus"
        }
    }

    public var accentColor: Color {
        switch self {
        case .newChat:       return .cyan
        case .runWorkflow:   return .green
        case .board:         return .indigo
        case .approvals:     return .orange
        case .agentStatus:   return .purple
        case .providers:     return .blue
        case .modelSelector: return .pink
        case .search:        return .secondary
        case .memoryVault:   return .yellow
        case .toolLog:       return .mint
        case .settings:      return .secondary
        case .spacer, .divider: return .secondary
        }
    }

    /// Items that can show a badge count
    public var supportsBadge: Bool {
        switch self {
        case .approvals, .agentStatus, .board: return true
        default: return false
        }
    }

    public var isLayoutElement: Bool {
        self == .spacer || self == .divider
    }
}

// MARK: - Per-item config

public struct ToolbarItemConfig: Codable, Sendable, Identifiable {
    public let id: String           // unique per slot (item.rawValue + UUID for duplicates)
    public var item: SwooshToolbarItem
    public var isVisible: Bool
    public var labelStyle: ToolbarLabelStyle
    public var customLabel: String? // nil = use displayName

    public enum ToolbarLabelStyle: String, Codable, Sendable, CaseIterable {
        case iconOnly
        case labelOnly
        case iconAndLabel
    }

    public init(item: SwooshToolbarItem, visible: Bool = true,
                labelStyle: ToolbarLabelStyle = .iconOnly, customLabel: String? = nil) {
        self.id = "\(item.rawValue)-\(UUID().uuidString.prefix(8))"
        self.item = item
        self.isVisible = visible
        self.labelStyle = labelStyle
        self.customLabel = customLabel
    }

    public var effectiveLabel: String { customLabel ?? item.displayName }
}

// MARK: - Toolbar config

public struct SwooshToolbarConfig: Codable, Sendable {
    public var items: [ToolbarItemConfig]
    public var globalLabelStyle: ToolbarItemConfig.ToolbarLabelStyle
    public var showBadges: Bool
    public var iconSize: CGFloat          // 16–28

    public static let `default` = SwooshToolbarConfig(
        items: [
            .init(item: .newChat),
            .init(item: .runWorkflow),
            .init(item: .divider),
            .init(item: .board),
            .init(item: .approvals),
            .init(item: .agentStatus),
            .init(item: .spacer),
            .init(item: .modelSelector),
            .init(item: .providers),
            .init(item: .divider),
            .init(item: .search),
            .init(item: .settings),
        ],
        globalLabelStyle: .iconOnly,
        showBadges: true,
        iconSize: 20
    )

    public static let developerPreset = SwooshToolbarConfig(
        items: [
            .init(item: .newChat),
            .init(item: .runWorkflow),
            .init(item: .divider),
            .init(item: .toolLog),
            .init(item: .agentStatus),
            .init(item: .memoryVault),
            .init(item: .spacer),
            .init(item: .modelSelector, labelStyle: .iconAndLabel),
            .init(item: .providers),
            .init(item: .search),
            .init(item: .settings),
        ],
        globalLabelStyle: .iconOnly,
        showBadges: true,
        iconSize: 20
    )

    public static let traderPreset = SwooshToolbarConfig(
        items: [
            .init(item: .newChat),
            .init(item: .divider),
            .init(item: .agentStatus),
            .init(item: .approvals),
            .init(item: .spacer),
            .init(item: .providers, labelStyle: .iconAndLabel),
            .init(item: .modelSelector, labelStyle: .iconAndLabel),
            .init(item: .settings),
        ],
        globalLabelStyle: .iconOnly,
        showBadges: true,
        iconSize: 22
    )

    public static let minimalPreset = SwooshToolbarConfig(
        items: [
            .init(item: .newChat),
            .init(item: .spacer),
            .init(item: .search),
            .init(item: .settings),
        ],
        globalLabelStyle: .iconOnly,
        showBadges: false,
        iconSize: 18
    )

    public static let focusPreset = SwooshToolbarConfig(
        items: [
            .init(item: .newChat),
            .init(item: .runWorkflow),
            .init(item: .spacer),
            .init(item: .approvals),
        ],
        globalLabelStyle: .iconAndLabel,
        showBadges: true,
        iconSize: 16
    )

    static let persistPath: URL = {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("toolbar.json")
    }()

    public func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.persistPath, options: .atomic)
    }

    public static func load() -> SwooshToolbarConfig {
        guard let data = try? Data(contentsOf: persistPath),
              let config = try? JSONDecoder().decode(SwooshToolbarConfig.self, from: data)
        else { return .default }
        return config
    }
}

// MARK: - Named presets

public struct ToolbarPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String
    public let config: SwooshToolbarConfig

    nonisolated(unsafe) public static let all: [ToolbarPreset] = [
        .init(id: "default",   name: "Default",   description: "Balanced layout for everyday use",
              icon: "square.grid.2x2", config: .default),
        .init(id: "developer", name: "Developer", description: "Tool log, agents, and model selector front-and-centre",
              icon: "hammer.fill", config: .developerPreset),
        .init(id: "trader",    name: "Trader",    description: "Approvals and agent status highlighted",
              icon: "chart.line.uptrend.xyaxis", config: .traderPreset),
        .init(id: "minimal",   name: "Minimal",   description: "Just chat, search, and settings",
              icon: "minus", config: .minimalPreset),
        .init(id: "focus",     name: "Focus",     description: "Task-focused — new chat and workflows only",
              icon: "target", config: .focusPreset),
    ]
}
