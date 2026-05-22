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
                ForEach(caps) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            MonoChip(text: c.risk.uppercased(),
                                     accent: c.enabled ? .green : .gold)
                            Text(c.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: c.enabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(c.enabled ? SwooshNeonTokens.Accent.green : SwooshNeonTokens.Canvas.text3)
                        }
                        HStack(spacing: 6) {
                            Text(c.status)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .lineLimit(1)
                            if !c.configured {
                                MonoChip(text: "setup", accent: .gold)
                            }
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
    @State private var records: RecordsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let r = records {
                KVRow(key: "total", value: "\(r.goals.count)")
                KVRow(key: "active", value: "\(r.goals.filter { $0.state == "active" }.count)", accent: .green)
                if let latest = r.goals.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                    KVRow(key: "latest", value: latest.state, accent: latest.state == "active" ? .green : .gold)
                }
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
struct ManifestsPanelView: View {
    @State private var records: RecordsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let r = records {
                let proposalCount = r.manifestations.reduce(0) { $0 + $1.proposalCount }
                KVRow(key: "passes", value: "\(r.manifestations.count)")
                KVRow(key: "proposals", value: "\(proposalCount)", accent: .gold)
                if let latest = r.manifestations.max(by: { $0.startedAt < $1.startedAt }) {
                    KVRow(key: "latest", value: latest.status, accent: latest.status == "completed" ? .green : .cyan)
                }
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

@MainActor
struct WorkflowsPanelView: View {
    @State private var records: RecordsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let r = records {
                KVRow(key: "board cards", value: "\(r.boardCards.count)")
                KVRow(key: "cron jobs", value: "\(r.cronJobs.count)", accent: .gold)
                KVRow(key: "ready", value: r.readiness.state.rawValue, accent: r.readiness.isReady ? .green : .gold)
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
struct TriggersPanelView: View {
    @State private var records: RecordsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let r = records {
                KVRow(key: "enabled", value: "\(r.cronJobs.filter(\.enabled).count)", accent: .green)
                KVRow(key: "paused", value: "\(r.cronJobs.filter { !$0.enabled }.count)")
                if let next = r.cronJobs.compactMap(\.nextRunAt).min() {
                    KVRow(key: "next", value: panelRelative(next), accent: .gold)
                }
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
struct ApprovalsPanelView: View {
    @State private var approvals: ApprovalsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            if loading {
                PanelLoadingRow()
            } else if let approvals {
                KVRow(key: "pending", value: "\(approvals.pending.count)", accent: approvals.pending.isEmpty ? .green : .gold)
                if let first = approvals.pending.first {
                    KVRow(key: "next", value: first.toolName, accent: .gold)
                }
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            approvals = try? await client.approvals()
            loading = false
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

@MainActor
struct ToolCatalogPanelView: View {
    @State private var catalog: ToolCatalogResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let catalog {
                KVRow(key: "registered", value: "\(catalog.tools.count)", accent: .green)
                KVRow(key: "toolsets", value: "\(catalog.toolsets.count)")
                KVRow(key: "humanOnly", value: "\(catalog.tools.filter { $0.approval == "humanOnly" }.count)", accent: .gold)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            catalog = try? await client.toolCatalog()
            loading = false
        }
    }
}

@MainActor
struct MCPServersPanelView: View {
    @State private var mcp: MCPServersResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let mcp {
                KVRow(key: "servers", value: "\(mcp.servers.count)")
                KVRow(key: "enabled", value: "\(mcp.servers.filter(\.enabled).count)", accent: .green)
                KVRow(key: "tools", value: "\(mcp.servers.reduce(0) { $0 + $1.importedToolCount })", accent: .gold)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            mcp = try? await client.mcpServers()
            loading = false
        }
    }
}

@MainActor
struct PluginsPanelView: View {
    @State private var plugins: PluginsResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let plugins {
                KVRow(key: "installed", value: "\(plugins.plugins.count)")
                KVRow(key: "enabled", value: "\(plugins.plugins.filter(\.enabled).count)", accent: .green)
                KVRow(key: "tools", value: "\(plugins.plugins.reduce(0) { $0 + $1.tools.count })", accent: .gold)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            plugins = try? await client.plugins()
            loading = false
        }
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

@MainActor
struct FirewallSummaryPanelView: View {
    @State private var config: RuntimeConfigResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let config {
                KVRow(key: "profile", value: config.permissionProfile ?? "unset", accent: .green)
                KVRow(key: "flags on", value: "\(config.safetyFlags.filter(\.enabled).count)")
                KVRow(key: "model tools", value: config.toolPolicy?.allowModelToolCalls == true ? "enabled" : "blocked", accent: config.toolPolicy?.allowModelToolCalls == true ? .green : .gold)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            config = try? await client.runtimeConfig()
            loading = false
        }
    }
}

@MainActor
struct SecretsPanelView: View {
    @State private var providers: ProvidersResponse?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                PanelLoadingRow()
            } else if let providers {
                KVRow(key: "configured", value: "\(providers.providers.filter(\.configured).count)", accent: .green)
                KVRow(key: "active", value: providers.activeProviderID ?? "none", accent: providers.activeProviderID == nil ? .gold : .cyan)
                Text("Keys stored in Keychain (ai.swoosh.secrets).")
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .task {
            guard let client = makeAPIClient() else { loading = false; return }
            providers = try? await client.providers()
            loading = false
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

@MainActor
func makeAPIClient() -> SwooshAPIClient? {
    SwooshDaemonClient.client()
}

func panelRelative(_ date: Date) -> String {
    RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
}
