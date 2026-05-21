// SwooshUI/Panels/PanelKind.swift — 0.9R Panel registry
//
// Full catalog of draggable panels available in any customizable Swoosh
// surface. Every module that exposes runtime state has a corresponding
// kind here; new kinds plug in by adding a case, listing in `allBuiltIn`,
// and mapping in `PanelLibrary.view(for:context:)`.

import Foundation
import SwooshGenerativeUI

/// What kind of work a panel does. Cases group by the underlying module
/// for readability; `custom` is reserved for user-saved generative
/// surfaces from `SwooshGenerativeUI`.
public enum PanelKind: Codable, Sendable, Hashable {

    // ── Conversation
    case agentShell           // The chat surface itself
    case recentChats          // List of past sessions
    case modelPicker          // Compact model + reasoning chip
    case voiceTranscript      // Live STT readout

    // ── Wallet + value
    case wallet
    case walletAnalytics
    case walletAssets
    case walletInsights
    case tradingCapabilities

    // ── Providers + models
    case providerStatus
    case localModels          // Ollama / MLX inventory
    case foundationModelStatus // Apple Foundation Models adapter

    // ── Agent self-improvement
    case skills
    case goals
    case manifests
    case memories

    // ── Work + flows
    case board                // Swoosh kanban
    case workflows
    case triggers
    case approvals            // Pending humanOnly approvals

    // ── Observability
    case auditLog
    case metrics              // Token / cost meter
    case costs
    case usage                // Provider-side usage report
    case observabilitySpans   // Open traces

    // ── Tools + integrations
    case toolCatalog
    case mcpServers
    case plugins
    case chatAdapters         // Slack / Discord / Telegram connectors

    // ── Knowledge + data
    case mediaGallery
    case scoutSources         // Recent personalization scans
    case spotlight            // CoreSpotlight indexer status

    // ── System
    case focusFilter          // Currently-active Focus mode binding
    case firewallSummary      // Permission gating overview
    case secrets              // Saved provider keys (read-only summary)

    // ── Decorative
    case agentOrb             // RealityView orb visualization
    case themePalette         // Live theme swatches

    // ── User-saved generative surface — content lives in
    //    GenerativeSurfaceHost under this id.
    case custom(surfaceID: String)

    // MARK: - Display metadata

    public var title: String {
        switch self {
        case .agentShell:           return "Chat"
        case .recentChats:          return "Recent Chats"
        case .modelPicker:          return "Model"
        case .voiceTranscript:      return "Voice"
        case .wallet:               return "Wallet"
        case .walletAnalytics:      return "PnL"
        case .walletAssets:         return "Assets"
        case .walletInsights:       return "Insights"
        case .tradingCapabilities:  return "Trading"
        case .providerStatus:       return "Providers"
        case .localModels:          return "Local Models"
        case .foundationModelStatus:return "Apple Foundation"
        case .skills:               return "Skills"
        case .goals:                return "Goals"
        case .manifests:            return "Manifests"
        case .memories:             return "Memories"
        case .board:                return "Board"
        case .workflows:            return "Workflows"
        case .triggers:             return "Triggers"
        case .approvals:            return "Approvals"
        case .auditLog:             return "Audit"
        case .metrics:              return "Metrics"
        case .costs:                return "Costs"
        case .usage:                return "Usage"
        case .observabilitySpans:   return "Traces"
        case .toolCatalog:          return "Tools"
        case .mcpServers:           return "MCP"
        case .plugins:              return "Plugins"
        case .chatAdapters:         return "Adapters"
        case .mediaGallery:         return "Media"
        case .scoutSources:         return "Scout"
        case .spotlight:            return "Spotlight"
        case .focusFilter:          return "Focus"
        case .firewallSummary:      return "Firewall"
        case .secrets:              return "Secrets"
        case .agentOrb:             return "Agent Orb"
        case .themePalette:         return "Theme"
        case .custom(let id):       return id
        }
    }

    public var systemImage: String {
        switch self {
        case .agentShell:           return "bubble.left.and.bubble.right"
        case .recentChats:          return "clock.arrow.circlepath"
        case .modelPicker:          return "cpu"
        case .voiceTranscript:      return "waveform"
        case .wallet:               return "creditcard"
        case .walletAnalytics:      return "chart.line.uptrend.xyaxis"
        case .walletAssets:         return "bitcoinsign.circle"
        case .walletInsights:       return "lightbulb"
        case .tradingCapabilities:  return "arrow.left.arrow.right.circle"
        case .providerStatus:       return "cloud"
        case .localModels:          return "memorychip"
        case .foundationModelStatus:return "apple.logo"
        case .skills:               return "star"
        case .goals:                return "target"
        case .manifests:            return "moon.stars"
        case .memories:             return "brain.head.profile"
        case .board:                return "square.grid.3x3"
        case .workflows:            return "arrow.triangle.branch"
        case .triggers:             return "bolt"
        case .approvals:            return "hand.raised"
        case .auditLog:             return "list.bullet.rectangle"
        case .metrics:              return "speedometer"
        case .costs:                return "dollarsign.circle"
        case .usage:                return "chart.bar.xaxis"
        case .observabilitySpans:   return "point.3.connected.trianglepath.dotted"
        case .toolCatalog:          return "wrench.and.screwdriver"
        case .mcpServers:           return "cable.connector"
        case .plugins:              return "puzzlepiece"
        case .chatAdapters:         return "bubble.left.and.text.bubble.right"
        case .mediaGallery:         return "photo.on.rectangle"
        case .scoutSources:         return "binoculars"
        case .spotlight:            return "magnifyingglass"
        case .focusFilter:          return "moon"
        case .firewallSummary:      return "shield.checkered"
        case .secrets:              return "key"
        case .agentOrb:             return "circle.hexagonpath"
        case .themePalette:         return "paintbrush"
        case .custom:               return "sparkles"
        }
    }

    public var blurb: String {
        switch self {
        case .agentShell:           return "Chat with the agent — generative surface + input."
        case .recentChats:          return "Past sessions. Tap to resume."
        case .modelPicker:          return "Switch model + reasoning depth."
        case .voiceTranscript:      return "Live readout while you dictate."
        case .wallet:               return "Connected accounts + balances."
        case .walletAnalytics:      return "PnL, daily change, open positions."
        case .walletAssets:         return "Token-by-token holdings."
        case .walletInsights:       return "Insights the agent has on your portfolio."
        case .tradingCapabilities:  return "Which DEXs and chains are wired up."
        case .providerStatus:       return "Provider keys, health, current selection."
        case .localModels:          return "Ollama + MLX inventory + RAM headroom."
        case .foundationModelStatus:return "Apple Foundation Models availability."
        case .skills:               return "Trust state + toggle skills in/out of prompt."
        case .goals:                return "Active goals + iteration progress."
        case .manifests:            return "Recent manifesting passes + proposals."
        case .memories:             return "Approved memories the agent sees."
        case .board:                return "Kanban view of agent work in progress."
        case .workflows:            return "Replayable workflows + recent runs."
        case .triggers:             return "Workflow triggers fired and pending."
        case .approvals:            return "humanOnly tool calls waiting for review."
        case .auditLog:             return "Recent agent steps + approvals."
        case .metrics:              return "Active session health at a glance."
        case .costs:                return "Spend per provider, this session and total."
        case .usage:                return "Token and request counts per provider."
        case .observabilitySpans:   return "Open traces with the slowest spans first."
        case .toolCatalog:          return "Registered tools + permission tier."
        case .mcpServers:           return "Connected MCP servers + tool counts."
        case .plugins:              return "Loaded plugins."
        case .chatAdapters:         return "Slack/Discord/Telegram bridges."
        case .mediaGallery:         return "Images and audio the agent has produced."
        case .scoutSources:         return "Latest personalization sources scanned."
        case .spotlight:            return "CoreSpotlight indexer status."
        case .focusFilter:          return "Current Focus mode + filter binding."
        case .firewallSummary:      return "Permission grants + denies overview."
        case .secrets:              return "Provider API keys stored in Keychain."
        case .agentOrb:             return "RealityView agent orb (decorative)."
        case .themePalette:         return "Active palette swatches."
        case .custom:               return "Saved generative surface."
        }
    }

    public var defaultAccent: NeonAccent {
        switch self {
        case .wallet, .walletAnalytics, .walletAssets, .walletInsights, .tradingCapabilities:
            return .green
        case .approvals, .firewallSummary, .secrets, .manifests:
            return .gold
        default:
            return .cyan
        }
    }

    /// Suggested baseline tile height in points. Lets the host reserve
    /// vertical space so the layout doesn't reflow as data loads.
    public var preferredHeight: CGFloat {
        switch self {
        case .agentShell:          return 360
        case .recentChats:         return 240
        case .auditLog, .workflows, .board, .mediaGallery, .observabilitySpans:
            return 280
        case .modelPicker, .voiceTranscript, .agentOrb, .themePalette, .focusFilter:
            return 96
        case .metrics, .costs, .usage, .walletAnalytics:
            return 160
        default:
            return 200
        }
    }

    /// Built-in kinds available in the add-panel sheet. Custom kinds are
    /// listed dynamically based on what the user has saved.
    public static let allBuiltIn: [PanelKind] = [
        .agentShell, .recentChats, .modelPicker, .voiceTranscript,
        .wallet, .walletAnalytics, .walletAssets, .walletInsights, .tradingCapabilities,
        .providerStatus, .localModels, .foundationModelStatus,
        .skills, .goals, .manifests, .memories,
        .board, .workflows, .triggers, .approvals,
        .auditLog, .metrics, .costs, .usage, .observabilitySpans,
        .toolCatalog, .mcpServers, .plugins, .chatAdapters,
        .mediaGallery, .scoutSources, .spotlight,
        .focusFilter, .firewallSummary, .secrets,
        .agentOrb, .themePalette,
    ]
}
