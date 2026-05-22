// SwooshUI/Panels/PanelLibrary.swift — 0.9R Kind → View dispatcher
//
// Single dispatcher mapping each `PanelKind` to its renderer. New kinds
// land here as a single case + their view in `Sources/SwooshUI/Panels/Kinds/`.
//
// Many panels share a "remote summary card" shape — they fetch a small
// blob from SwooshAPIClient on appear and render a compact summary plus
// an "open in window" affordance. `RemoteSummaryCard` is the helper.

import SwiftUI
import SwooshClient

/// Host-supplied context every panel kind has access to.
public struct PanelHostContext {
    public let shell: AgentShellModel
    /// Shared client for read-only summary endpoints. Optional so the
    /// host stays renderable even when no daemon is reachable.
    public let client: SwooshAPIClient?

    public init(shell: AgentShellModel, client: SwooshAPIClient? = nil) {
        self.shell = shell
        self.client = client
    }
}

public enum PanelLibrary {

    @ViewBuilder
    public static func view(
        for instance: PanelInstance,
        context: PanelHostContext
    ) -> some View {
        switch instance.kind {

        // Conversation
        case .agentShell:           AgentShellPanelView(shell: context.shell)
        case .recentChats:          RecentChatsPanelView()
        case .modelPicker:          ModelPickerPanelView(shell: context.shell)
        case .voiceTranscript:      VoiceTranscriptPanelView(shell: context.shell)

        // Wallet
        case .wallet:               WalletPanelView()
        case .walletAnalytics:      WalletAnalyticsPanelView()
        case .walletAssets:         WalletAssetsPanelView()
        case .walletInsights:       WalletInsightsPanelView()
        case .tradingCapabilities:  TradingCapabilitiesPanelView()
        case .jupiterDocs:          JupiterDocsPanelView()
        case .defiDocs:             DeFiDocsPanelView()
        case .launchpadDocs:        LaunchpadDocsPanelView()

        // Providers + models
        case .providerStatus:       ProviderStatusPanelView()
        case .localModels:          LocalModelsPanelView()
        case .foundationModelStatus:FoundationModelStatusPanelView()

        // Self-improvement
        case .skills:               SkillsPanelView()
        case .goals:                GoalsPanelView()
        case .manifests:            ManifestsPanelView()
        case .memories:             MemoriesPanelView()

        // Work + flows
        case .board:                BoardPanelView()
        case .workflows:            WorkflowsPanelView()
        case .triggers:             TriggersPanelView()
        case .approvals:            ApprovalsPanelView()

        // Observability
        case .auditLog:             AuditPanelView()
        case .metrics:              MetricsPanelView()
        case .costs:                CostsPanelView()
        case .usage:                UsagePanelView()
        case .observabilitySpans:   SpansPanelView()

        // Tools + integrations
        case .toolCatalog:          ToolCatalogPanelView()
        case .mcpServers:           MCPServersPanelView()
        case .plugins:              PluginsPanelView()
        case .chatAdapters:         ChatAdaptersPanelView()

        // Knowledge + data
        case .mediaGallery:         MediaGalleryPanelView()
        case .scoutSources:         ScoutSourcesPanelView()
        case .spotlight:            SpotlightPanelView()

        // System
        case .focusFilter:          FocusFilterPanelView()
        case .firewallSummary:      FirewallSummaryPanelView()
        case .secrets:              SecretsPanelView()

        // Decorative
        case .agentOrb:             AgentOrbPanelView()
        case .themePalette:         ThemePalettePanelView()

        // Custom
        case .custom(let surfaceID):
            CustomSurfacePanelView(shell: context.shell, surfaceID: surfaceID)
        }
    }
}
