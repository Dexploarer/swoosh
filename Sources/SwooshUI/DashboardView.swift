// SwooshUI/DashboardView.swift — Native Swoosh dashboard
//
// Not a demo. The real agent control panel. macOS-only: the iOS app
// has its own root surface and doesn't use NavigationSplitView the
// same way.

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshVault
import SwooshFirewall
import SwooshBoard
import SwooshFlow
import SwooshTools
import SwooshGenerativeUI
import Foundation

public struct DashboardView: View {
    @State private var themeManager = ThemeManager()
    @State private var selectedTab: DashboardTab = .workspace
    @State private var runtime = DashboardRuntimeSnapshot.empty
    @State private var panelStore = PanelLayoutStore()
    @State private var toolbarManager = SwooshToolbarManager()
    @State private var editingPanels = false
    @Environment(AgentShellModel.self) private var shell
    let voice: VoiceMode?

    public init(voice: VoiceMode? = nil) {
        self.voice = voice
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .background(SwooshNeonTokens.Canvas.bg)
        } detail: {
            detailView
                .background(SwooshNeonTokens.Canvas.bg)
        }
        .swooshToolbar(
            manager: toolbarManager,
            pendingApprovals: runtime.pendingApprovalCount,
            runningAgents: runtime.status?.chat == true ? 1 : 0,
            boardCards: runtime.boardCards.count
        )
        .swooshTheme(themeManager.currentTheme)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .swooshToolbarAction)) { event in
            guard let raw = event.object as? String,
                  let item = SwooshToolbarItem(rawValue: raw) else { return }
            handleToolbarAction(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swooshOpenDashboardTab)) { event in
            guard let raw = event.object as? String,
                  let tab = DashboardTab(rawValue: raw) else { return }
            selectedTab = tab
        }
        .onAppear {
            themeManager.load(from: ThemeManager.defaultURL)
        }
        .task {
            runtime = await DashboardRuntimeSnapshot.load()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(DashboardSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Detour")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .workspace:
            PanelHost(
                store: panelStore,
                surface: "dashboard",
                context: PanelHostContext(shell: shell),
                editing: $editingPanels
            )
            .environment(shell)
        case .chat:        AgentShellView(shell: shell, mode: .window)
        case .voice:
            if let voice {
                VoicePane(voice: voice, shell: shell)
            } else {
                ContentUnavailableView(
                    "Voice unavailable",
                    systemImage: "mic.slash",
                    description: Text("Voice mode wasn't injected into this DashboardView instance.")
                )
            }
        case .generative:  GenerativeUIPane()
        case .agents:      AgentsPane(snapshot: runtime)
        case .board:       BoardPane(cards: runtime.boardCards)
        case .workflows:   WorkflowsPane(snapshot: runtime)
        case .triggers:    TriggersPane(snapshot: runtime)
        case .goals:       GoalsDashboardPane(snapshot: runtime)
        case .manifesting: ManifestingDashboardPane(snapshot: runtime)
        case .vault:       MemoryVaultPane(snapshot: runtime)
        case .skills:      SkillsPane(snapshot: runtime)
        case .wallet:      PanelKindDashboardPane(kind: .wallet)
        case .trading:     PanelKindDashboardPane(kind: .tradingCapabilities)
        case .jupiter:     PanelKindDashboardPane(kind: .jupiterDocs)
        case .defi:        PanelKindDashboardPane(kind: .defiDocs)
        case .launchpads:  PanelKindDashboardPane(kind: .launchpadDocs)
        case .tools:       ToolsPane(snapshot: runtime)
        case .firewall:    FirewallPane(snapshot: runtime)
        case .secrets:     PanelKindDashboardPane(kind: .secrets)
        case .providers:   ProvidersConfigPane()
        case .localModels: LocalModelsPane(snapshot: runtime)
        case .mcp:         MCPPane(snapshot: runtime)
        case .plugins:     PluginsPane(snapshot: runtime)
        case .chatAdapters: PanelKindDashboardPane(kind: .chatAdapters)
        case .media:       PanelKindDashboardPane(kind: .mediaGallery)
        case .scout:       PanelKindDashboardPane(kind: .scoutSources)
        case .spotlight:   PanelKindDashboardPane(kind: .spotlight)
        case .approvals:   ApprovalsPane(snapshot: runtime)
        case .auditLog:    AuditLogPane(snapshot: runtime)
        case .usage:       PanelKindDashboardPane(kind: .usage)
        case .costs:       PanelKindDashboardPane(kind: .costs)
        case .traces:      PanelKindDashboardPane(kind: .observabilitySpans)
        case .benchmarks:  BenchmarksPane(snapshot: runtime)
        case .appearance:  AppearanceEditorView(manager: themeManager)
        case .settings:    RuntimeSettingsPane(runtimeConfig: runtime.runtimeConfig, readinessRows: runtime.settingsRows)
        }
    }

    private func handleToolbarAction(_ item: SwooshToolbarItem) {
        switch item {
        case .newChat:
            shell.clearConversation()
            selectedTab = .chat
        case .runWorkflow:
            selectedTab = .workflows
        case .board:
            selectedTab = .board
        case .approvals:
            selectedTab = .approvals
        case .agentStatus:
            selectedTab = .agents
        case .providers:
            selectedTab = .providers
        case .modelSelector:
            selectedTab = .localModels
        case .search:
            selectedTab = .spotlight
        case .memoryVault:
            selectedTab = .vault
        case .toolLog:
            selectedTab = .auditLog
        case .settings:
            selectedTab = .settings
        case .spacer, .divider:
            break
        }
    }
}

// MARK: - Tab enum

enum DashboardSection: String, CaseIterable, Identifiable {
    case agent
    case work
    case knowledge
    case value
    case system
    case observe
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return "Agent"
        case .work: return "Work"
        case .knowledge: return "Knowledge"
        case .value: return "Value"
        case .system: return "System"
        case .observe: return "Observe"
        case .app: return "App"
        }
    }

    var tabs: [DashboardTab] {
        switch self {
        case .agent: return [.workspace, .chat, .voice, .generative, .agents]
        case .work: return [.board, .workflows, .triggers, .goals, .manifesting]
        case .knowledge: return [.vault, .skills, .scout, .spotlight]
        case .value: return [.wallet, .trading, .jupiter, .defi, .launchpads]
        case .system: return [.tools, .firewall, .secrets, .providers, .localModels, .mcp, .plugins, .chatAdapters, .media]
        case .observe: return [.approvals, .auditLog, .usage, .costs, .traces, .benchmarks]
        case .app: return [.appearance, .settings]
        }
    }
}

enum DashboardTab: String, Identifiable, Hashable {
    case workspace
    case chat, voice, generative, agents, board, workflows, triggers
    case goals, manifesting
    case vault, skills
    case wallet, trading, jupiter, defi, launchpads
    case tools, firewall, secrets, providers, localModels, mcp, plugins, chatAdapters, media, scout, spotlight
    case approvals, auditLog, usage, costs, traces, benchmarks
    case appearance, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .chat: return "Chat"
        case .voice: return "Voice"
        case .generative: return "Generative UI"
        case .agents: return "Agents"
        case .board: return "Board"
        case .workflows: return "Workflows"
        case .triggers: return "Triggers"
        case .goals: return "Goals"
        case .manifesting: return "Manifesting"
        case .vault: return "Memory Vault"
        case .skills: return "Skills"
        case .wallet: return "Wallet"
        case .trading: return "Trading"
        case .jupiter: return "Jupiter"
        case .defi: return "DeFi"
        case .launchpads: return "Launchpads"
        case .tools: return "Tools"
        case .firewall: return "Firewall"
        case .secrets: return "Secrets"
        case .providers: return "Providers"
        case .localModels: return "Local Models"
        case .mcp: return "MCP"
        case .plugins: return "Plugins"
        case .chatAdapters: return "Chat Adapters"
        case .media: return "Media"
        case .scout: return "Scout"
        case .spotlight: return "Spotlight"
        case .approvals: return "Approvals"
        case .auditLog: return "Audit Log"
        case .usage: return "Usage"
        case .costs: return "Costs"
        case .traces: return "Traces"
        case .benchmarks: return "Benchmarks"
        case .appearance: return "Appearance"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .workspace: return "square.grid.2x2"
        case .chat: return "bubble.left.and.bubble.right"
        case .voice: return "mic.circle"
        case .generative: return "rectangle.on.rectangle.angled"
        case .agents: return "person.3"
        case .board: return "square.grid.3x3"
        case .workflows: return "arrow.triangle.branch"
        case .triggers: return "bolt"
        case .goals: return "target"
        case .manifesting: return "moon.stars"
        case .vault: return "brain.head.profile"
        case .skills: return "star"
        case .wallet: return "creditcard"
        case .trading: return "arrow.left.arrow.right.circle"
        case .jupiter: return "sparkles"
        case .defi: return "point.3.connected.trianglepath.dotted"
        case .launchpads: return "flag.checkered"
        case .tools: return "wrench.and.screwdriver"
        case .firewall: return "shield.checkered"
        case .secrets: return "key"
        case .providers: return "cloud"
        case .localModels: return "cpu"
        case .mcp: return "cable.connector"
        case .plugins: return "puzzlepiece"
        case .chatAdapters: return "bubble.left.and.text.bubble.right"
        case .media: return "photo.on.rectangle"
        case .scout: return "binoculars"
        case .spotlight: return "magnifyingglass"
        case .approvals: return "hand.raised"
        case .auditLog: return "list.bullet.rectangle"
        case .usage: return "chart.bar.xaxis"
        case .costs: return "dollarsign.circle"
        case .traces: return "point.3.connected.trianglepath.dotted"
        case .benchmarks: return "chart.bar"
        case .appearance: return "paintbrush"
        case .settings: return "gear"
        }
    }
}

// MARK: - Runtime panes

struct RuntimePane: View {
    let title: String
    let icon: String
    let rows: [RuntimeRow]

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    RuntimeRowView(row: row)
                }
            } header: {
                Label(title, systemImage: icon)
            }
        }
        .navigationTitle(title)
    }
}

struct RuntimeRowView: View {
    let row: RuntimeRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(row.title, systemImage: row.systemImage)
            Spacer()
            Text(row.value)
                .foregroundStyle(row.level.color)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct BoardPane: View {
    let cards: [BoardCardSummary]

    var body: some View {
        List(cards) { card in
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title).font(.headline)
                Text(card.detail).foregroundStyle(.secondary)
                Text(card.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Swoosh Board")
    }
}

struct RuntimeSettingsPane: View {
    let runtimeConfig: SwooshRuntimeConfig?
    let readinessRows: [RuntimeRow]

    var body: some View {
        List {
            Section {
                if let runtimeConfig {
                    RuntimeRowView(row: RuntimeRow("Setup mode", runtimeConfig.setupMode, systemImage: "switch.2"))
                    RuntimeRowView(row: RuntimeRow("Permission profile", runtimeConfig.permissionProfile, systemImage: "person.badge.key"))
                    RuntimeRowView(row: RuntimeRow("Model path", runtimeConfig.modelPath, systemImage: "brain"))
                    RuntimeRowView(row: RuntimeRow("Daemon", "\(runtimeConfig.daemonHost):\(runtimeConfig.daemonPort)", systemImage: "network"))
                    RuntimeRowView(row: RuntimeRow("Diagnostic fallback", runtimeConfig.localDiagnosticFallback ? "Enabled" : "Disabled", systemImage: "stethoscope"))
                } else {
                    RuntimeRowView(row: RuntimeRow("Runtime config", "Not configured", systemImage: "gear", level: .warning))
                }
            } header: {
                Label("Runtime", systemImage: "gear")
            }

            if let policy = runtimeConfig?.toolPolicy {
                Section {
                    RuntimeRowView(row: RuntimeRow("Model tool calls", policy.allowModelToolCalls ? "Enabled" : "Disabled", systemImage: "wrench.and.screwdriver", level: policy.allowModelToolCalls ? .good : .warning))
                    RuntimeRowView(row: RuntimeRow("Max calls per turn", "\(policy.maxToolCallsPerTurn)", systemImage: "number"))
                    RuntimeRowView(row: RuntimeRow("Max chain depth", "\(policy.maxToolChainDepth)", systemImage: "point.3.connected.trianglepath.dotted"))
                    RuntimeRowView(row: RuntimeRow("Human-only from model", policy.allowHumanOnlyFromModel ? "Allowed" : "Blocked", systemImage: "hand.raised", level: policy.allowHumanOnlyFromModel ? .warning : .good))
                    RuntimeRowView(row: RuntimeRow("Critical tools from model", policy.allowCriticalToolsFromModel ? "Allowed" : "Blocked", systemImage: "exclamationmark.triangle", level: policy.allowCriticalToolsFromModel ? .warning : .good))
                    RuntimeRowView(row: RuntimeRow("Medium-risk approval", policy.requireApprovalForMediumRiskAndAbove ? "Required" : "Optional", systemImage: "checkmark.seal", level: policy.requireApprovalForMediumRiskAndAbove ? .good : .warning))
                } header: {
                    Label("Tool Policy", systemImage: "wrench.and.screwdriver")
                }
            }

            if let safetyConfig = runtimeConfig?.safetyConfig {
                Section {
                    ForEach(safetyRows(safetyConfig)) { row in
                        RuntimeRowView(row: row)
                    }
                } header: {
                    Label("Safety Flags", systemImage: "shield.checkered")
                }
            }

            Section {
                ForEach(readinessRows) { row in
                    RuntimeRowView(row: row)
                }
            } header: {
                Label("Readiness", systemImage: "checkmark.seal")
            }
        }
        .navigationTitle("Settings")
    }

    private func safetyRows(_ config: SwooshSafetyConfig) -> [RuntimeRow] {
        [
            flagRow("Autonomous trading", config.autonomousTradingEnabled),
            flagRow("Swap execution", config.swapExecutionEnabled),
            flagRow("Portfolio recommendations", config.portfolioRecommendationsEnabled),
            flagRow("Private-key custody", config.privateKeyCustodyEnabled),
            flagRow("Seed phrase ingestion", config.seedPhraseIngestionEnabled),
            flagRow("Cookie ingestion", config.cookieIngestionEnabled),
            flagRow("Shell to blockchain bridge", config.shellToBlockchainBridgeEnabled),
            flagRow("Model self-approval", config.modelSelfApprovalEnabled),
            flagRow("Mainnet writes by default", config.mainnetWritesByDefault),
        ]
    }

    private func flagRow(_ title: String, _ enabled: Bool) -> RuntimeRow {
        RuntimeRow(title, enabled ? "Enabled" : "Disabled", systemImage: enabled ? "checkmark.circle" : "xmark.circle", level: enabled ? .warning : .good)
    }
}

struct RuntimeRow: Identifiable, Sendable {
    enum Level: Sendable {
        case normal
        case good
        case warning

        var color: Color {
            switch self {
            case .normal: .secondary
            case .good: .green
            case .warning: .orange
            }
        }
    }

    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
    let level: Level

    init(_ title: String, _ value: String, systemImage: String = "circle", level: Level = .normal) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.level = level
    }
}

extension RuntimeRow.Level {
    init(_ status: SwooshReadinessStatus) {
        switch status {
        case .ready:
            self = .good
        case .warning, .blocked:
            self = .warning
        }
    }
}

public struct DashboardRuntimeSnapshot: Sendable {
    var status: AgentStatusResponse?
    var providers: [ProviderSummary]
    var boardCards: [BoardCardSummary]
    var metrics: [MetricCounter]
    var usage: UsageResponse?
    var skills: [SkillSummary]
    var readiness: SwooshReadinessReport
    var records: RecordsResponse?
    var approvals: ApprovalsResponse?
    var runtimeConfig: SwooshRuntimeConfig?
    var local: LocalRuntimeCounts
    var daemonReachable: Bool

    static let empty = DashboardRuntimeSnapshot(
        status: nil,
        providers: [],
        boardCards: [],
        metrics: [],
        usage: nil,
        skills: [],
        readiness: SwooshReadinessDetector().report(inputs: SwooshReadinessInputs(daemonReachable: false)),
        records: nil,
        approvals: nil,
        runtimeConfig: try? SwooshConfigStore().load(SwooshRuntimeConfig.self),
        local: LocalRuntimeCounts.load(),
        daemonReachable: false
    )

    static func load() async -> DashboardRuntimeSnapshot {
        let local = LocalRuntimeCounts.load()
        guard let client = SwooshDashboardClient.make() else {
            return DashboardRuntimeSnapshot.empty.with(local: local)
        }
        do {
            async let status = client.agentStatus()
            async let providers = client.providers()
            async let cards = client.boardCards()
            async let metrics = client.metrics()
            async let usage = client.usage()
            async let skills = client.skills()
            async let readiness = client.readiness()
            async let records = client.records()
            let providerResponse = try await providers
            let cardResponse = try await cards
            let metricResponse = try await metrics
            let usageResponse = try await usage
            let skillResponse = try await skills
            let readinessResponse = try await readiness
            let recordsResponse = try await records
            let approvalsResponse = try? await client.approvals()
            return DashboardRuntimeSnapshot(
                status: try await status,
                providers: providerResponse.providers,
                boardCards: cardResponse.cards,
                metrics: metricResponse.counters,
                usage: usageResponse,
                skills: skillResponse.skills,
                readiness: readinessResponse,
                records: recordsResponse,
                approvals: approvalsResponse,
                runtimeConfig: local.runtimeConfig,
                local: local,
                daemonReachable: true
            )
        } catch {
            return DashboardRuntimeSnapshot.empty.with(local: local)
        }
    }

    func with(local: LocalRuntimeCounts) -> DashboardRuntimeSnapshot {
        var copy = self
        copy.local = local
        copy.runtimeConfig = local.runtimeConfig
        return copy
    }

    var chatRows: [RuntimeRow] {
        [
            RuntimeRow("Readiness", readiness.state.rawValue, systemImage: "checkmark.seal", level: readinessLevel),
            RuntimeRow("Daemon", daemonReachable ? "Reachable" : "Offline", systemImage: "network", level: daemonReachable ? .good : .warning),
            RuntimeRow("Chat turns", "\(usage?.chatTurns ?? 0)", systemImage: "bubble.left.and.bubble.right"),
            RuntimeRow("Provider", status?.provider ?? readiness.component(id: "model.provider")?.detail ?? "Not checked", systemImage: "cpu"),
            RuntimeRow("Model", status?.model ?? readiness.component(id: "model.provider")?.detail ?? "Not checked", systemImage: "brain"),
        ]
    }

    var agentRows: [RuntimeRow] {
        [
            RuntimeRow("Kernel", readiness.component(id: "daemon.chat")?.detail ?? "Not checked", systemImage: "person.crop.circle.badge.checkmark", level: readiness.component(id: "daemon.chat")?.status == .ready ? .good : .warning),
            RuntimeRow("Last chat", usage?.lastChatAt?.formatted(date: .abbreviated, time: .shortened) ?? "None", systemImage: "clock"),
            RuntimeRow("Approved memory references", "\(usage?.approvedMemoryReferences ?? 0)", systemImage: "brain.head.profile"),
        ]
    }

    var workflowRows: [RuntimeRow] { [RuntimeRow("Drafts", "\(local.workflowDrafts)", systemImage: "doc.text")] }
    var triggerRows: [RuntimeRow] { [RuntimeRow("Cron jobs", "\(local.cronJobs)", systemImage: "clock.arrow.circlepath")] }
    var memoryRows: [RuntimeRow] { [RuntimeRow("Memory files", "\(local.memoryFiles)", systemImage: "brain.head.profile")] }
    var skillRows: [RuntimeRow] { [RuntimeRow("Promptable skills", "\(skills.count)", systemImage: "star.fill", level: skills.isEmpty ? .warning : .good)] }
    var toolRows: [RuntimeRow] { metrics.map { RuntimeRow($0.id, "\($0.value)", systemImage: "number") } }
    var firewallRows: [RuntimeRow] { [RuntimeRow("Policy", "Firewall-gated tools", systemImage: "shield.checkered", level: .good)] }
    var localModelRows: [RuntimeRow] { [RuntimeRow("Model directories", "\(local.localModels)", systemImage: "cpu")] }
    var mcpRows: [RuntimeRow] { [RuntimeRow("Configured files", "\(local.mcpFiles)", systemImage: "cable.connector")] }
    var pluginRows: [RuntimeRow] { [RuntimeRow("Configured files", "\(local.pluginFiles)", systemImage: "puzzlepiece")] }
    var approvalRows: [RuntimeRow] { [RuntimeRow("Local approval queue", "Human-only gated", systemImage: "hand.raised", level: .good)] }
    var auditRows: [RuntimeRow] { [RuntimeRow("Log files", "\(local.logFiles)", systemImage: "list.bullet.rectangle")] }
    var benchmarkRows: [RuntimeRow] { [RuntimeRow("Artifacts", "\(local.artifacts)", systemImage: "chart.bar")] }
    var pendingApprovalCount: Int { approvals?.pending.count ?? 0 }
    var settingsRows: [RuntimeRow] {
        readiness.components.map { component in
            RuntimeRow(component.title, component.detail, systemImage: "gear", level: RuntimeRow.Level(component.status))
        }
    }

    private var readinessLevel: RuntimeRow.Level {
        switch readiness.state {
        case .ready:
            return .good
        case .degraded:
            return .warning
        case .blocked:
            return .warning
        }
    }
}

private enum SwooshDashboardClient {
    static func make() -> SwooshAPIClient? {
        SwooshDaemonClient.client()
    }
}

struct LocalRuntimeCounts: Sendable {
    let hasConfig: Bool
    let memoryFiles: Int
    let workflowDrafts: Int
    let cronJobs: Int
    let localModels: Int
    let mcpFiles: Int
    let pluginFiles: Int
    let logFiles: Int
    let artifacts: Int
    let runtimeConfig: SwooshRuntimeConfig?

    static func load() -> LocalRuntimeCounts {
        let root = swooshHomeDirectoryForCurrentUser().appendingPathComponent(".swoosh", isDirectory: true)
        return LocalRuntimeCounts(
            hasConfig: FileManager.default.fileExists(atPath: root.appendingPathComponent("config.json").path),
            memoryFiles: countFiles(root.appendingPathComponent("memories", isDirectory: true), extensionFilter: "json"),
            workflowDrafts: countFiles(root.appendingPathComponent("workflows", isDirectory: true), extensionFilter: "json"),
            cronJobs: countFiles(root.appendingPathComponent("cron", isDirectory: true), extensionFilter: "json"),
            localModels: countDirectories(root.appendingPathComponent("models", isDirectory: true)),
            mcpFiles: countFiles(root.appendingPathComponent("mcp", isDirectory: true), extensionFilter: "json"),
            pluginFiles: countFiles(root.appendingPathComponent("plugins", isDirectory: true), extensionFilter: "json"),
            logFiles: countFiles(root.appendingPathComponent("logs", isDirectory: true), extensionFilter: "log"),
            artifacts: countFiles(root.appendingPathComponent("artifacts", isDirectory: true), extensionFilter: nil),
            runtimeConfig: try? SwooshConfigStore().load(SwooshRuntimeConfig.self)
        )
    }

    private static func countFiles(_ url: URL, extensionFilter: String?) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return 0 }
        guard let extensionFilter else { return urls.count }
        return urls.filter { $0.pathExtension == extensionFilter }.count
    }

    private static func countDirectories(_ url: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }
        return urls.filter { ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }.count
    }
}

#Preview {
    DashboardView()
}

#endif
