// SwooshUI/Panels/Kinds/PanelKinds.swift — 0.9R All panel views
//
// One file per kind would be neat but slows discovery; one file with all
// of them lets the catalog stay scannable and shares the small helpers
// (RemoteSummaryRow, MonoChip, KVRow) without exporting them broadly.
//
// Data-backed panels (Wallet*, Recent, Providers, Skills, Audit, …) call
// SwooshAPIClient on appear. Summary-only panels render a tight "status +
// open in window" capsule until their corresponding window surfaces ship.

import SwiftUI
import SwooshClient
import SwooshGenerativeUI
import SwooshModels

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared primitives
// ═══════════════════════════════════════════════════════════════════

/// One mono-styled key-value row — the workhorse of every summary panel.
struct KVRow: View {
    let key: String
    let value: String
    var accent: NeonAccent = .cyan

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(accent.color)
        }
    }
}

/// Mono chip used inline (e.g. "OPEN · 3").
struct MonoChip: View {
    let text: String
    var accent: NeonAccent = .cyan
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(accent.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(accent.color.opacity(0.3), lineWidth: 0.5))
            .clipShape(Capsule())
    }
}

/// Placeholder while a panel waits on its first network call.
struct PanelLoadingRow: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }
}

/// Error row when an endpoint fails. Compact and non-alarming.
struct PanelErrorRow: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            .lineLimit(2)
    }
}

/// Compact "open in window" CTA used by every panel that has a full view
/// available elsewhere.
struct OpenInWindowButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SwooshNeonTokens.Accent.cyan)
        }
        .buttonStyle(.plain)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Conversation
// ═══════════════════════════════════════════════════════════════════

struct AgentShellPanelView: View {
    @Bindable var shell: AgentShellModel
    var body: some View {
        AgentShellView(shell: shell, mode: .tray)
            .frame(minHeight: 320)
    }
}

struct RecentChatsPanelView: View {
    @Environment(AgentShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if shell.messages.isEmpty {
                Text("No messages yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            } else {
                ForEach(shell.messages.suffix(5)) { msg in
                    HStack(alignment: .top, spacing: 6) {
                        MonoChip(text: msg.role == .user ? "YOU" : "AGENT",
                                 accent: msg.role == .user ? .cyan : .green)
                        Text(msg.text)
                            .font(.system(size: 12))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

struct ModelPickerPanelView: View {
    @Bindable var shell: AgentShellModel
    var body: some View {
        HStack {
            ModelPicker(
                models: [],     // Fetched downstream from the picker's caller
                selectedModelID: $shell.selectedModelID,
                effort: $shell.selectedEffort
            )
            Spacer()
        }
    }
}

struct VoiceTranscriptPanelView: View {
    @Bindable var shell: AgentShellModel
    var body: some View {
        HStack(spacing: 10) {
            VoiceWaveformView(level: shell.speech.audioLevel, active: shell.voice == .listening)
            Text(shell.speech.transcript.isEmpty ? "Idle." : shell.speech.transcript)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .lineLimit(2)
            Spacer()
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Wallet
// ═══════════════════════════════════════════════════════════════════

@MainActor
struct WalletPanelView: View {
    @Environment(AgentShellModel.self) private var shell
    @State private var dash: WalletDashboardResponse?
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let dash {
                KVRow(key: "status", value: dash.connected ? "connected" : "not paired",
                      accent: dash.connected ? .green : .gold)
                if let label = dash.walletLabel {
                    KVRow(key: "label", value: label)
                }
                KVRow(key: "assets", value: "\(dash.assets.count)")
                KVRow(key: "open positions", value: "\(dash.analytics.openPositions)")
            } else if let errorText {
                PanelErrorRow(message: errorText)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = makeAPIClient() else {
            errorText = "Daemon not reachable."
            loading = false
            return
        }
        do {
            dash = try await client.walletDashboard()
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

@MainActor
struct WalletAnalyticsPanelView: View {
    @State private var summary: WalletAnalyticsSummary?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let s = summary {
                KVRow(key: "value", value: s.totalValueUSD ?? "—", accent: .green)
                KVRow(key: "pnl %", value: s.totalPnLPercent ?? "—",
                      accent: percentAccent(s.totalPnLPercent))
                KVRow(key: "24h Δ", value: s.dailyChangePercent ?? "—",
                      accent: percentAccent(s.dailyChangePercent))
                KVRow(key: "unrealized", value: s.unrealizedPnLUSD ?? "—")
                KVRow(key: "realized", value: s.realizedPnLUSD ?? "—")
            } else {
                Text("No data.")
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            summary = try? await client.walletDashboard().analytics
            loading = false
        }
    }

    private func percentAccent(_ value: String?) -> NeonAccent {
        guard let value, let n = Double(value.replacingOccurrences(of: "%", with: "")) else {
            return .cyan
        }
        return n >= 0 ? .green : .gold
    }
}

@MainActor
struct WalletAssetsPanelView: View {
    @State private var assets: [WalletAssetSummary] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if assets.isEmpty {
                Text("No assets.")
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            } else {
                ForEach(assets.prefix(5)) { asset in
                    HStack {
                        MonoChip(text: asset.chain.uppercased())
                        Text(asset.symbol)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        Text(asset.valueUSD ?? asset.quantity)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Accent.green)
                    }
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            assets = (try? await client.walletDashboard().assets) ?? []
            loading = false
        }
    }
}

@MainActor
struct WalletInsightsPanelView: View {
    @State private var insights: [WalletInsightSummary] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if insights.isEmpty {
                Text("No insights yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            } else {
                ForEach(insights.prefix(4)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Text(item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                            .lineLimit(2)
                    }
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            insights = (try? await client.walletDashboard().insights) ?? []
            loading = false
        }
    }
}

@MainActor
struct TradingCapabilitiesPanelView: View {
    @State private var caps: [WalletTradingCapabilitySummary] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else {
                ForEach(caps.prefix(6)) { c in
                    HStack {
                        MonoChip(text: c.risk.uppercased(),
                                 accent: c.enabled ? .green : .gold)
                        Text(c.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        if c.enabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10))
                                .foregroundStyle(SwooshNeonTokens.Accent.green)
                        }
                    }
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            caps = (try? await client.walletDashboard().capabilities) ?? []
            loading = false
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Providers + models
// ═══════════════════════════════════════════════════════════════════

@MainActor
struct ProviderStatusPanelView: View {
    @State private var providers: ProviderStatusResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let p = providers, !p.providers.isEmpty {
                ForEach(p.providers.prefix(5), id: \.id) { provider in
                    HStack {
                        Circle()
                            .fill(provider.configured
                                  ? SwooshNeonTokens.Accent.green
                                  : SwooshNeonTokens.Accent.gold)
                            .frame(width: 6, height: 6)
                        Text(provider.name)
                            .font(.system(size: 12))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        if provider.active {
                            MonoChip(text: "active", accent: .green)
                        }
                    }
                }
            } else {
                Text("No providers configured.")
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            providers = try? await client.providerStatus()
            loading = false
        }
    }
}

@MainActor
struct LocalModelsPanelView: View {
    @State private var hardware: HardwareProfile = .detectCurrent()
    @State private var recommendedAgents: [CatalogEntry] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            KVRow(key: "chip", value: hardware.chip)
            KVRow(key: "ram", value: String(format: "%.0f GB", hardware.totalMemoryGB))
            KVRow(key: "max tier", value: hardware.maxTier.rawValue)
            if loading {
                PanelLoadingRow()
            } else if !recommendedAgents.isEmpty {
                Divider().background(SwooshNeonTokens.Line.rule).padding(.vertical, 2)
                Text("RECOMMENDED AGENTS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                ForEach(recommendedAgents.prefix(3)) { model in
                    HStack {
                        Text(model.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        MonoChip(text: model.parameterCount, accent: .cyan)
                        MonoChip(text: "\(Int(model.estimatedMemoryGB))GB", accent: .cyan)
                    }
                }
            }
        }
        .task {
            let catalog = ModelCatalog(hardware: hardware)
            recommendedAgents = await catalog
                .forRole(.agent)
                .filter { $0.estimatedMemoryGB <= hardware.usableMemoryGB }
                .sorted { $0.estimatedMemoryGB > $1.estimatedMemoryGB }
            loading = false
        }
    }
}

struct FoundationModelStatusPanelView: View {
    var body: some View {
        HStack {
            Image(systemName: "apple.logo")
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Text("Apple Foundation Models")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Spacer()
            MonoChip(text: "available", accent: .green)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Self-improvement
// ═══════════════════════════════════════════════════════════════════

@MainActor
struct SkillsPanelView: View {
    @State private var skills: SkillsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let s = skills {
                KVRow(key: "promoted", value: "\(s.skills.filter { $0.trust == "promoted" }.count)", accent: .green)
                KVRow(key: "drafts", value: "\(s.skills.filter { $0.trust == "draft" }.count)", accent: .gold)
                KVRow(key: "total", value: "\(s.skills.count)")
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            skills = try? await client.skills()
            loading = false
        }
    }
}

@MainActor
struct GoalsPanelView: View {
    var body: some View {
        Text("Active goals view — drive off GoalRunner state. Open in window for details.")
            .font(.system(size: 11))
            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            .lineLimit(3)
    }
}

@MainActor
struct ManifestsPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "last pass", value: "—")
            KVRow(key: "proposals", value: "0", accent: .gold)
        }
    }
}

@MainActor
struct MemoriesPanelView: View {
    @State private var memories: MemoriesResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let m = memories {
                KVRow(key: "approved", value: "\(m.approved.count)", accent: .green)
                KVRow(key: "pending", value: "\(m.pending.count)", accent: .gold)
                KVRow(key: "rejected", value: "\(m.rejected.count)")
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            memories = try? await client.memories()
            loading = false
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Work + flows
// ═══════════════════════════════════════════════════════════════════

@MainActor
struct BoardPanelView: View {
    @State private var lanes: BoardLanesResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let lanes {
                ForEach(lanes.lanes.prefix(4), id: \.id) { lane in
                    HStack {
                        Text(lane.title)
                            .font(.system(size: 12))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        MonoChip(text: "\(lane.cardCount)")
                    }
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            lanes = try? await client.boardLanes()
            loading = false
        }
    }
}

struct WorkflowsPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "registered", value: "—")
            KVRow(key: "recent runs", value: "—")
        }
    }
}

struct TriggersPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "active", value: "—")
            KVRow(key: "fired today", value: "—")
        }
    }
}

struct ApprovalsPanelView: View {
    var body: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(SwooshNeonTokens.Accent.gold)
            Text("Pending humanOnly approvals will land here.")
                .font(.system(size: 11))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .lineLimit(2)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Observability
// ═══════════════════════════════════════════════════════════════════

@MainActor
struct AuditPanelView: View {
    @State private var records: RecordsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let r = records {
                KVRow(key: "goals", value: "\(r.goals.count)")
                KVRow(key: "manifestations", value: "\(r.manifestations.count)", accent: .gold)
                KVRow(key: "board cards", value: "\(r.boardCards.count)")
                KVRow(key: "cron jobs", value: "\(r.cronJobs.count)")
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            records = try? await client.records()
            loading = false
        }
    }
}

@MainActor
struct MetricsPanelView: View {
    @State private var metrics: MetricsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let m = metrics, !m.counters.isEmpty {
                ForEach(m.counters.prefix(5)) { c in
                    KVRow(key: c.id, value: "\(c.value)")
                }
            } else {
                Text("No counters yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            metrics = try? await client.metrics()
            loading = false
        }
    }
}

@MainActor
struct CostsPanelView: View {
    @State private var usage: UsageResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let u = usage {
                KVRow(key: "chat turns", value: "\(u.chatTurns)", accent: .green)
                KVRow(key: "memory refs", value: "\(u.approvedMemoryReferences)")
                if let last = u.lastChatAt {
                    KVRow(key: "last chat", value: relative(last))
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            usage = try? await client.usage()
            loading = false
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        return f.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
struct UsagePanelView: View {
    @State private var usage: UsageResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let u = usage {
                KVRow(key: "chat turns", value: "\(u.chatTurns)")
                KVRow(key: "approved refs", value: "\(u.approvedMemoryReferences)")
                if let last = u.lastChatAt {
                    KVRow(key: "last activity", value: relative(last))
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            usage = try? await client.usage()
            loading = false
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct SpansPanelView: View {
    var body: some View {
        Text("Recent slow spans — taps open the trace in window.")
            .font(.system(size: 11))
            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tools + integrations
// ═══════════════════════════════════════════════════════════════════

struct ToolCatalogPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "registered", value: "—")
            KVRow(key: "humanOnly", value: "—", accent: .gold)
        }
    }
}

struct MCPServersPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "connected", value: "—")
            KVRow(key: "tools exposed", value: "—")
        }
    }
}

struct PluginsPanelView: View {
    var body: some View {
        Text("Loaded plugins — open Plugins tab for details.")
            .font(.system(size: 11))
            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
    }
}

@MainActor
struct ChatAdaptersPanelView: View {
    @State private var adapters: ChatAdaptersResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let a = adapters {
                ForEach(a.adapters.prefix(4)) { adapter in
                    HStack {
                        Circle()
                            .fill(adapter.enabled ? SwooshNeonTokens.Accent.green : SwooshNeonTokens.Canvas.text3)
                            .frame(width: 6, height: 6)
                        Text(adapter.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Spacer()
                        if adapter.configured {
                            MonoChip(text: "ok", accent: .green)
                        } else {
                            MonoChip(text: "setup", accent: .gold)
                        }
                    }
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            adapters = try? await client.chatAdapters()
            loading = false
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Knowledge + data
// ═══════════════════════════════════════════════════════════════════

@MainActor
struct MediaGalleryPanelView: View {
    @State private var media: MediaGalleryResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let m = media {
                KVRow(key: "items", value: "\(m.items.count)")
                if let latest = m.items.first {
                    KVRow(key: "latest", value: latest.title)
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            media = try? await client.mediaGallery()
            loading = false
        }
    }
}

struct ScoutSourcesPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "last scan", value: "—")
            KVRow(key: "sources active", value: "—")
        }
    }
}

struct SpotlightPanelView: View {
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            Text("CoreSpotlight indexer · idle")
                .font(.system(size: 11))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - System
// ═══════════════════════════════════════════════════════════════════

struct FocusFilterPanelView: View {
    var body: some View {
        HStack {
            Image(systemName: "moon.fill")
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            Text("No Focus active.")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            Spacer()
        }
    }
}

struct FirewallSummaryPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "grants this session", value: "—", accent: .green)
            KVRow(key: "denies", value: "—", accent: .gold)
        }
    }
}

struct SecretsPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KVRow(key: "providers configured", value: "—")
            Text("Keys stored in Keychain (ai.swoosh.secrets).")
                .font(.system(size: 10))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Decorative
// ═══════════════════════════════════════════════════════════════════

struct AgentOrbPanelView: View {
    var body: some View {
        HStack {
            Spacer()
            Circle()
                .fill(SwooshNeonTokens.Accent.cyan.opacity(0.4))
                .frame(width: 56, height: 56)
                .shadow(color: SwooshNeonTokens.Accent.cyan.opacity(0.8), radius: 18)
                .overlay(
                    Circle().strokeBorder(SwooshNeonTokens.Accent.cyan, lineWidth: 1)
                )
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct ThemePalettePanelView: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([NeonAccent.cyan, .gold, .green], id: \.self) { accent in
                Circle()
                    .fill(accent.color)
                    .frame(width: 16, height: 16)
                    .shadow(color: accent.color.opacity(0.5), radius: 4)
            }
            Spacer()
            Text("3 accents")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Custom (saved generative surface)
// ═══════════════════════════════════════════════════════════════════

struct CustomSurfacePanelView: View {
    let shell: AgentShellModel
    let surfaceID: String

    var body: some View {
        GenerativeSurfaceView(host: shell.surfaceHost, surfaceID: surfaceID)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared API client builder
// ═══════════════════════════════════════════════════════════════════

/// Build a one-shot client to the local daemon. Reads the bearer token
/// from `~/.swoosh/api_token`. Returns nil if the token isn't there yet.
@MainActor
func makeAPIClient() -> SwooshAPIClient? {
    let path = ("~/.swoosh/api_token" as NSString).expandingTildeInPath
    let token = try? String(contentsOfFile: path, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let host = URL(string: "http://127.0.0.1:7777") else { return nil }
    return SwooshAPIClient(baseURL: host, token: token)
}
