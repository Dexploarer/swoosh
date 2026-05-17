// SwooshUI/MenuBar/MenuBarConfig.swift — Fully user-customizable menu bar layout
//
// The user has complete control over what appears in the menu bar popover,
// the order of sections, which providers to show, card layout, and more.
// Persisted to ~/.swoosh/menubar.json. Hot-reloads.

import SwiftUI
import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Menu bar section types
// ═══════════════════════════════════════════════════════════════════

/// Every element that can appear in the menu bar popover.
public enum MenuBarSection: String, Codable, Sendable, CaseIterable, Identifiable {
    case providerStatus      // Provider credential status + health
    case usageMeters         // Per-provider usage bars with reset countdowns
    case costTracker         // Spend / credits / billing summary
    case quickActions        // Common actions (chat, workflow, scout)
    case approvals           // Pending approval count + peek
    case boardSummary        // Board card counts by lane
    case workflowStatus      // Active workflow runs
    case agentStatus         // Running agents / subagents
    case memoryVault         // Recent memories
    case systemHealth        // CPU, memory, inference latency
    case notifications       // Recent alerts
    case recentChats         // Last N chat threads
    case modelSelector       // Quick model switch
    case mcpServers          // Connected MCP server status
    case localModels         // Ollama / MLX model status
    case customWidget        // User-defined widget slot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .providerStatus:  return "Provider Status"
        case .usageMeters:     return "Usage Meters"
        case .costTracker:     return "Cost Tracker"
        case .quickActions:    return "Quick Actions"
        case .approvals:       return "Approvals"
        case .boardSummary:    return "Board Summary"
        case .workflowStatus:  return "Workflow Status"
        case .agentStatus:     return "Agent Status"
        case .memoryVault:     return "Memory Vault"
        case .systemHealth:    return "System Health"
        case .notifications:   return "Notifications"
        case .recentChats:     return "Recent Chats"
        case .modelSelector:   return "Model Selector"
        case .mcpServers:      return "MCP Servers"
        case .localModels:     return "Local Models"
        case .customWidget:    return "Custom Widget"
        }

    }

    public var defaultIcon: String {
        switch self {
        case .providerStatus:  return "cloud.fill"
        case .usageMeters:     return "chart.bar.fill"
        case .costTracker:     return "dollarsign.circle.fill"
        case .quickActions:    return "bolt.fill"
        case .approvals:       return "hand.raised.fill"
        case .boardSummary:    return "square.grid.3x3.fill"
        case .workflowStatus:  return "arrow.triangle.branch"
        case .agentStatus:     return "person.3.fill"
        case .memoryVault:     return "brain.head.profile.fill"
        case .systemHealth:    return "heart.fill"
        case .notifications:   return "bell.fill"
        case .recentChats:     return "bubble.left.and.bubble.right.fill"
        case .modelSelector:   return "cpu.fill"
        case .mcpServers:      return "cable.connector"
        case .localModels:     return "desktopcomputer"
        case .customWidget:    return "puzzlepiece.fill"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Section configuration
// ═══════════════════════════════════════════════════════════════════

/// Per-section configuration — controls visibility, order, and display options.
public struct MenuBarSectionConfig: Codable, Sendable, Identifiable {
    public var section: MenuBarSection
    public var enabled: Bool
    public var collapsed: Bool
    public var maxItems: Int?          // Limit visible items (e.g. top 3 providers)
    public var customTitle: String?    // Override section title
    public var customIcon: String?     // Override SF Symbol name

    public var id: String { section.rawValue }

    public init(section: MenuBarSection, enabled: Bool = true,
                collapsed: Bool = false, maxItems: Int? = nil,
                customTitle: String? = nil, customIcon: String? = nil) {
        self.section = section
        self.enabled = enabled
        self.collapsed = collapsed
        self.maxItems = maxItems
        self.customTitle = customTitle
        self.customIcon = customIcon
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Icon mode
// ═══════════════════════════════════════════════════════════════════

/// How the menu bar icon appears in the system tray.
public enum MenuBarIconMode: String, Codable, Sendable, CaseIterable {
    case swooshLogo          // Default Swoosh icon
    case providerMeter       // CodexBar-style usage meter bar
    case statusDot           // Minimal dot (green/yellow/red)
    case providerIcon        // Show active provider's icon
    case custom              // User-provided SF Symbol name
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Full menu bar configuration
// ═══════════════════════════════════════════════════════════════════

/// The complete menu bar configuration. Serialized to ~/.swoosh/menubar.json.
public struct MenuBarConfiguration: Codable, Sendable {
    public var presetName: String
    public var iconMode: MenuBarIconMode
    public var customIconName: String?

    /// Popover dimensions
    public var popoverWidth: CGFloat
    public var popoverMaxHeight: CGFloat

    /// Sections in display order
    public var sections: [MenuBarSectionConfig]

    /// Provider filter — which providers to show (nil = all discovered)
    public var visibleProviders: [String]?

    /// Refresh interval in seconds
    public var refreshInterval: TimeInterval

    /// Card style
    public var cardStyle: CardStyle

    /// Show section headers
    public var showSectionHeaders: Bool

    /// Compact mode — tighter spacing, smaller fonts
    public var compactMode: Bool

    public enum CardStyle: String, Codable, Sendable, CaseIterable {
        case glass       // Liquid glass cards
        case flat        // Flat material design
        case bordered    // Bordered cards with subtle shadow
        case minimal     // No card chrome, just content
    }

    public init(presetName: String = "Custom",
                iconMode: MenuBarIconMode = .swooshLogo,
                customIconName: String? = nil,
                popoverWidth: CGFloat = 380,
                popoverMaxHeight: CGFloat = 600,
                sections: [MenuBarSectionConfig] = [],
                visibleProviders: [String]? = nil,
                refreshInterval: TimeInterval = 120,
                cardStyle: CardStyle = .glass,
                showSectionHeaders: Bool = true,
                compactMode: Bool = false) {
        self.presetName = presetName
        self.iconMode = iconMode
        self.customIconName = customIconName
        self.popoverWidth = popoverWidth
        self.popoverMaxHeight = popoverMaxHeight
        self.sections = sections
        self.visibleProviders = visibleProviders
        self.refreshInterval = refreshInterval
        self.cardStyle = cardStyle
        self.showSectionHeaders = showSectionHeaders
        self.compactMode = compactMode
    }
}
