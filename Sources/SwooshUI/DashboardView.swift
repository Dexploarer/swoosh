// SwooshUI/DashboardView.swift — Native Swoosh dashboard
//
// Not a demo. The real agent control panel.

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshVault
import SwooshFirewall
import SwooshBoard
import SwooshFlow
import Foundation

public struct DashboardView: View {
    @State private var themeManager = ThemeManager()
    @State private var selectedTab: DashboardTab = .chat
    @State private var runtime = DashboardRuntimeSnapshot.empty

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
                .swooshGlass()
        } detail: {
            detailView
        }
        .swooshGlassContainer()
        .swooshThemedBackground()
        .swooshTheme(themeManager.currentTheme)
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
            Section("Agent") {
                Label("Chat", systemImage: "bubble.left.and.bubble.right").tag(DashboardTab.chat)
                Label("Agents", systemImage: "person.3").tag(DashboardTab.agents)
            }

            Section("Work") {
                Label("Board", systemImage: "square.grid.3x3").tag(DashboardTab.board)
                Label("Workflows", systemImage: "arrow.triangle.branch").tag(DashboardTab.workflows)
                Label("Triggers", systemImage: "bolt").tag(DashboardTab.triggers)
            }

            Section("Knowledge") {
                Label("Memory Vault", systemImage: "brain.head.profile").tag(DashboardTab.vault)
                Label("Skills", systemImage: "star").tag(DashboardTab.skills)
            }

            Section("System") {
                Label("Tools", systemImage: "wrench.and.screwdriver").tag(DashboardTab.tools)
                Label("Firewall", systemImage: "shield.checkered").tag(DashboardTab.firewall)
                Label("Providers", systemImage: "cloud").tag(DashboardTab.providers)
                Label("Local Models", systemImage: "cpu").tag(DashboardTab.localModels)
                Label("MCP", systemImage: "cable.connector").tag(DashboardTab.mcp)
                Label("Plugins", systemImage: "puzzlepiece").tag(DashboardTab.plugins)
            }

            Section("Observe") {
                Label("Approvals", systemImage: "hand.raised").tag(DashboardTab.approvals)
                Label("Audit Log", systemImage: "list.bullet.rectangle").tag(DashboardTab.auditLog)
                Label("Benchmarks", systemImage: "chart.bar").tag(DashboardTab.benchmarks)
            }

            Section {
                Label("Appearance", systemImage: "paintbrush").tag(DashboardTab.appearance)
                Label("Settings", systemImage: "gear").tag(DashboardTab.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Swoosh")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .chat:        RuntimePane(title: "Chat", icon: "bubble.left.and.bubble.right", rows: runtime.chatRows)
        case .agents:      RuntimePane(title: "Active Agents", icon: "person.3", rows: runtime.agentRows)
        case .board:       BoardPane(cards: runtime.boardCards)
        case .workflows:   RuntimePane(title: "Workflows", icon: "arrow.triangle.branch", rows: runtime.workflowRows)
        case .triggers:    RuntimePane(title: "Triggers", icon: "bolt", rows: runtime.triggerRows)
        case .vault:       RuntimePane(title: "Memory Vault", icon: "brain.head.profile", rows: runtime.memoryRows)
        case .skills:      RuntimePane(title: "Skills", icon: "star", rows: runtime.skillRows)
        case .tools:       RuntimePane(title: "Tools", icon: "wrench.and.screwdriver", rows: runtime.toolRows)
        case .firewall:    RuntimePane(title: "Agent Firewall", icon: "shield.checkered", rows: runtime.firewallRows)
        case .providers:   ProviderStatusPane()
        case .localModels: RuntimePane(title: "Local Models", icon: "cpu", rows: runtime.localModelRows)
        case .mcp:         RuntimePane(title: "MCP Servers", icon: "cable.connector", rows: runtime.mcpRows)
        case .plugins:     RuntimePane(title: "Plugins", icon: "puzzlepiece", rows: runtime.pluginRows)
        case .approvals:   RuntimePane(title: "Approval Center", icon: "hand.raised", rows: runtime.approvalRows)
        case .auditLog:    RuntimePane(title: "Audit Log", icon: "list.bullet.rectangle", rows: runtime.auditRows)
        case .benchmarks:  RuntimePane(title: "Benchmarks", icon: "chart.bar", rows: runtime.benchmarkRows)
        case .appearance:  AppearanceEditorView(manager: themeManager)
        case .settings:    RuntimePane(title: "Settings", icon: "gear", rows: runtime.settingsRows)
        }
    }
}

// MARK: - Tab enum

enum DashboardTab: Hashable {
    case chat, agents, board, workflows, triggers
    case vault, skills
    case tools, firewall, providers, localModels, mcp, plugins
    case approvals, auditLog, benchmarks
    case appearance, settings
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
                    HStack(alignment: .firstTextBaseline) {
                        Label(row.title, systemImage: row.systemImage)
                        Spacer()
                        Text(row.value)
                            .foregroundStyle(row.level.color)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Label(title, systemImage: icon)
            }
        }
        .navigationTitle(title)
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

struct DashboardRuntimeSnapshot: Sendable {
    var status: AgentStatusResponse?
    var providers: [ProviderSummary]
    var boardCards: [BoardCardSummary]
    var metrics: [MetricCounter]
    var usage: UsageResponse?
    var skills: [SkillSummary]
    var readiness: SwooshReadinessReport
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
            let providerResponse = try await providers
            let cardResponse = try await cards
            let metricResponse = try await metrics
            let usageResponse = try await usage
            let skillResponse = try await skills
            let readinessResponse = try await readiness
            return DashboardRuntimeSnapshot(
                status: try await status,
                providers: providerResponse.providers,
                boardCards: cardResponse.cards,
                metrics: metricResponse.counters,
                usage: usageResponse,
                skills: skillResponse.skills,
                readiness: readinessResponse,
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
        let config = SwooshConfigStore()
        let runtime = try? config.load(SwooshRuntimeConfig.self)
        let fileToken = (try? String(contentsOf: config.apiTokenFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = TokenStore.load() ?? fileToken
        let configuredBase = URL(string: "http://\(runtime?.daemonHost ?? "127.0.0.1"):\(runtime?.daemonPort ?? 8787)")!
        let base = HostStore.current ?? configuredBase
        return SwooshAPIClient(baseURL: base, token: token)
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

    static func load() -> LocalRuntimeCounts {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".swoosh", isDirectory: true)
        return LocalRuntimeCounts(
            hasConfig: FileManager.default.fileExists(atPath: root.appendingPathComponent("config.json").path),
            memoryFiles: countFiles(root.appendingPathComponent("memories", isDirectory: true), extensionFilter: "json"),
            workflowDrafts: countFiles(root.appendingPathComponent("workflows", isDirectory: true), extensionFilter: "json"),
            cronJobs: countFiles(root.appendingPathComponent("cron", isDirectory: true), extensionFilter: "json"),
            localModels: countDirectories(root.appendingPathComponent("models", isDirectory: true)),
            mcpFiles: countFiles(root.appendingPathComponent("mcp", isDirectory: true), extensionFilter: "json"),
            pluginFiles: countFiles(root.appendingPathComponent("plugins", isDirectory: true), extensionFilter: "json"),
            logFiles: countFiles(root.appendingPathComponent("logs", isDirectory: true), extensionFilter: "log"),
            artifacts: countFiles(root.appendingPathComponent("artifacts", isDirectory: true), extensionFilter: nil)
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
