// SwooshUI/MenuBar/MenuBarPresets.swift — Pre-configured menu bar layouts
//
// Users can pick a preset and customize from there, or start from scratch.

import Foundation

public enum MenuBarPreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case swoosh          // Full Swoosh experience
    case codexBar        // CodexBar-style: providers + usage meters + cost
    case minimal         // Just status dot + quick actions
    case developer       // Providers + board + workflows + agents
    case monitor         // System health + costs + usage
    case agent           // Agent-first: chats + agents + approvals
    case custom          // User-defined

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .swoosh:    return "Detour"
        case .codexBar:  return "CodexBar"
        case .minimal:   return "Minimal"
        case .developer: return "Developer"
        case .monitor:   return "Monitor"
        case .agent:     return "Agent"
        case .custom:    return "Custom"
        }
    }

    public var description: String {
        switch self {
        case .swoosh:    return "Full Detour command center: providers, agents, board, approvals, and workflows"
        case .codexBar:  return "Provider usage meters, cost tracking, and reset countdowns"
        case .minimal:   return "Clean and quiet — just a status dot and quick actions"
        case .developer: return "Focused on code: providers, board cards, workflows, and MCP"
        case .monitor:   return "Observability: system health, costs, usage, and notifications"
        case .agent:     return "Agent-first: active chats, running agents, and pending approvals"
        case .custom:    return "Build your own layout from scratch"
        }
    }

    public var configuration: MenuBarConfiguration {
        switch self {
        case .swoosh:    return Self.swooshConfig
        case .codexBar:  return Self.codexBarConfig
        case .minimal:   return Self.minimalConfig
        case .developer: return Self.developerConfig
        case .monitor:   return Self.monitorConfig
        case .agent:     return Self.agentConfig
        case .custom:    return Self.customConfig
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Preset configurations
    // ═══════════════════════════════════════════════════════════════

    /// Full Detour experience (preset key stays `.swoosh` for back-compat
    /// with stored user layouts; only the user-facing name is rebranded).
    private static var swooshConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "Detour",
            iconMode: .swooshLogo,
            popoverWidth: 400,
            popoverMaxHeight: 700,
            sections: [
                MenuBarSectionConfig(section: .quickActions),
                MenuBarSectionConfig(section: .providerStatus),
                MenuBarSectionConfig(section: .approvals),
                MenuBarSectionConfig(section: .agentStatus),
                MenuBarSectionConfig(section: .boardSummary, collapsed: true),
                MenuBarSectionConfig(section: .workflowStatus, collapsed: true),
                MenuBarSectionConfig(section: .usageMeters, collapsed: true),
                MenuBarSectionConfig(section: .costTracker, collapsed: true),
                MenuBarSectionConfig(section: .notifications),
                MenuBarSectionConfig(section: .systemHealth, collapsed: true),
            ],
            refreshInterval: 120,
            cardStyle: .glass,
            showSectionHeaders: true
        )
    }

    /// CodexBar-style: usage meters, costs, reset countdowns
    private static var codexBarConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "CodexBar",
            iconMode: .providerMeter,
            popoverWidth: 380,
            popoverMaxHeight: 600,
            sections: [
                MenuBarSectionConfig(section: .providerStatus),
                MenuBarSectionConfig(section: .usageMeters),
                MenuBarSectionConfig(section: .costTracker),
                MenuBarSectionConfig(section: .systemHealth, collapsed: true),
            ],
            refreshInterval: 60,
            cardStyle: .bordered,
            showSectionHeaders: true,
            compactMode: true
        )
    }

    /// Minimal: status dot + quick actions
    private static var minimalConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "Minimal",
            iconMode: .statusDot,
            popoverWidth: 320,
            popoverMaxHeight: 400,
            sections: [
                MenuBarSectionConfig(section: .quickActions),
                MenuBarSectionConfig(section: .providerStatus, maxItems: 3),
                MenuBarSectionConfig(section: .notifications),
            ],
            refreshInterval: 300,
            cardStyle: .minimal,
            showSectionHeaders: false,
            compactMode: true
        )
    }

    /// Developer: code-focused
    private static var developerConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "Developer",
            iconMode: .swooshLogo,
            popoverWidth: 400,
            popoverMaxHeight: 650,
            sections: [
                MenuBarSectionConfig(section: .providerStatus),
                MenuBarSectionConfig(section: .boardSummary),
                MenuBarSectionConfig(section: .workflowStatus),
                MenuBarSectionConfig(section: .agentStatus),
                MenuBarSectionConfig(section: .mcpServers),
                MenuBarSectionConfig(section: .localModels, collapsed: true),
                MenuBarSectionConfig(section: .approvals),
            ],
            refreshInterval: 60,
            cardStyle: .glass,
            showSectionHeaders: true
        )
    }

    /// Monitor: observability-focused
    private static var monitorConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "Monitor",
            iconMode: .providerMeter,
            popoverWidth: 380,
            popoverMaxHeight: 650,
            sections: [
                MenuBarSectionConfig(section: .systemHealth),
                MenuBarSectionConfig(section: .usageMeters),
                MenuBarSectionConfig(section: .costTracker),
                MenuBarSectionConfig(section: .providerStatus),
                MenuBarSectionConfig(section: .notifications),
            ],
            refreshInterval: 30,
            cardStyle: .bordered,
            showSectionHeaders: true
        )
    }

    /// Agent-first
    private static var agentConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "Agent",
            iconMode: .swooshLogo,
            popoverWidth: 380,
            popoverMaxHeight: 600,
            sections: [
                MenuBarSectionConfig(section: .recentChats),
                MenuBarSectionConfig(section: .agentStatus),
                MenuBarSectionConfig(section: .approvals),
                MenuBarSectionConfig(section: .quickActions),
                MenuBarSectionConfig(section: .modelSelector),
                MenuBarSectionConfig(section: .providerStatus, collapsed: true),
            ],
            refreshInterval: 30,
            cardStyle: .glass,
            showSectionHeaders: true
        )
    }

    /// Empty starting point for full customization
    private static var customConfig: MenuBarConfiguration {
        MenuBarConfiguration(
            presetName: "Custom",
            iconMode: .swooshLogo,
            popoverWidth: 380,
            popoverMaxHeight: 600,
            sections: MenuBarSection.allCases.map {
                MenuBarSectionConfig(section: $0, enabled: false)
            },
            refreshInterval: 120,
            cardStyle: .glass,
            showSectionHeaders: true
        )
    }
}
