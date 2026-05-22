// SwooshUI/DashboardPanes/DashboardPanes.swift — Rich panes for every
// dashboard tab. Replaces the generic `RuntimePane(rows:)` stubs.
//
// Each pane reads from the already-loaded `DashboardRuntimeSnapshot`
// (passed in by `DashboardView`) so we don't double-fetch, and most
// also fetch their own slice of data on appear via SwooshAPIClient.
// When the daemon is unreachable, every pane gracefully degrades to a
// "Daemon offline" state instead of looking broken.

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared building blocks
// ═══════════════════════════════════════════════════════════════════

struct PaneHeader: View {
    @Environment(\.swooshTheme) var theme
    let title: String
    let icon: String
    let subtitle: String?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.accent.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
        .padding(.bottom, 4)
    }
}

struct PaneCard<Content: View>: View {
    @Environment(\.swooshTheme) var theme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.textPrimary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.textPrimary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

struct StatBadge: View {
    @Environment(\.swooshTheme) var theme
    let value: String
    let label: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.textPrimary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                )
        )
    }
}

struct OfflineBanner: View {
    @Environment(\.swooshTheme) var theme
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text(reason)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}

struct ListRow: View {
    @Environment(\.swooshTheme) var theme
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    let trailing: String?
    var trailingTint: Color = .secondary
    var onTap: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.58))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(trailingTint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                .fill(hovering && onTap != nil ? theme.textPrimary.opacity(0.04) : Color.clear)
        )

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            content
        }
    }
}

// Generic scaffolding all panes share.
struct DashboardPane<Content: View>: View {
    @Environment(\.swooshTheme) var theme
    let title: String
    let icon: String
    let subtitle: String?
    var headerTrailing: AnyView? = nil
    let content: () -> Content

    init(title: String, icon: String, subtitle: String? = nil,
         headerTrailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(title: title, icon: icon, subtitle: subtitle, trailing: headerTrailing)
                content()
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .background(SwooshNeonTokens.Canvas.bg)
    }
}

struct PanelKindDashboardPane: View {
    @Environment(AgentShellModel.self) private var shell
    let kind: PanelKind

    var body: some View {
        DashboardPane(
            title: kind.title,
            icon: kind.systemImage,
            subtitle: kind.blurb
        ) {
            PaneCard {
                PanelLibrary.view(
                    for: PanelInstance(kind: kind),
                    context: PanelHostContext(shell: shell, client: SwooshDaemonClient.client())
                )
                .padding(16)
                .frame(minHeight: min(kind.preferredHeight, 420), alignment: .topLeading)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Generative UI
// ═══════════════════════════════════════════════════════════════════

struct GenerativeUIPane: View {
    @Environment(AgentShellModel.self) private var shell
    @Environment(\.swooshTheme) var theme

    init() {}

    public var body: some View {
        DashboardPane(
            title: "Generative UI",
            icon: "rectangle.on.rectangle.angled",
            subtitle: "Surfaces the agent has emitted in this session"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                statBadges
                surfaceList
                actionLog
            }
        }
    }

    private var statBadges: some View {
        HStack(spacing: 10) {
            StatBadge(value: "\(shell.surfaceHost.surfaces.count)",
                      label: "Surfaces",
                      tint: .cyan)
            StatBadge(value: shell.activeSurfaceID,
                      label: "Active",
                      tint: .yellow)
            StatBadge(value: shell.isAwaitingResponse ? "Yes" : "No",
                      label: "Awaiting",
                      tint: shell.isAwaitingResponse ? .green : .secondary)
        }
    }

    @ViewBuilder
    private var surfaceList: some View {
        PaneCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("LIVE SURFACES")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                let ids = Array(shell.surfaceHost.surfaces.keys).sorted()
                if ids.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "rectangle.dashed")
                                .font(.system(size: 28))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text("No surfaces yet")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                            Text("The agent will populate surfaces here as it emits generative UI.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(24)
                } else {
                    ForEach(ids, id: \.self) { id in
                        ListRow(
                            icon: id == shell.activeSurfaceID ? "rectangle.fill" : "rectangle",
                            iconTint: id == shell.activeSurfaceID ? .cyan : theme.textPrimary.opacity(0.55),
                            title: id,
                            subtitle: id == shell.activeSurfaceID ? "Active" : nil,
                            trailing: nil,
                            onTap: { shell.activeSurfaceID = id }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionLog: some View {
        PaneCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("HOST CONTROLS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ListRow(
                    icon: "arrow.uturn.left",
                    iconTint: .orange,
                    title: "Reset to main surface",
                    subtitle: "Clears all alternative surfaces and routes the agent back to `main`.",
                    trailing: nil,
                    onTap: { shell.activeSurfaceID = "main" }
                )
                ListRow(
                    icon: "rectangle.on.rectangle.angled",
                    iconTint: .cyan,
                    title: "Project to desktop overlay",
                    subtitle: "Open the floating overlay so surfaces render on the desktop while voice mode is active.",
                    trailing: nil,
                    onTap: {
                        NotificationCenter.default.post(
                            name: Notification.Name("ai.swoosh.showDesktopOverlay"),
                            object: nil
                        )
                    }
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Approvals
// ═══════════════════════════════════════════════════════════════════

struct ApprovalsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var pendingRows: [ApprovalSummary] = []
    @State private var historyRows: [ApprovalSummary] = []
    @State private var isLoading = false
    @State private var error: String?

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Approvals",
            icon: "hand.raised.fill",
            subtitle: "Pending tool calls awaiting human approval"
        ) {
            if let error {
                OfflineBanner(reason: error)
            }
            if !snapshot.daemonReachable {
                OfflineBanner(reason: "Daemon offline — approval queue is unreachable.")
            }

            HStack(spacing: 10) {
                StatBadge(value: "\(pendingRows.count)", label: "Pending", tint: .yellow)
                StatBadge(value: "\(historyRows.count)", label: "History", tint: .blue)
                StatBadge(
                    value: snapshot.readiness.component(id: "approvals")?.detail ?? "Gated",
                    label: "Policy",
                    tint: .green
                )
            }

            PaneCard {
                sectionHeader("PENDING")
                if pendingRows.isEmpty {
                    emptyState(icon: "checkmark.seal", text: "No approvals waiting.")
                } else {
                    ForEach(pendingRows) { row in
                        approvalRow(row)
                    }
                }
            }

            PaneCard {
                sectionHeader("RECENT DECISIONS")
                if historyRows.isEmpty {
                    emptyState(icon: "clock", text: "No decisions yet.")
                } else {
                    ForEach(historyRows) { row in
                        ListRow(
                            icon: row.status == "denied" ? "xmark.circle.fill" : "checkmark.circle.fill",
                            iconTint: row.status == "denied" ? .red : .green,
                            title: row.toolName,
                            subtitle: row.inputPreview,
                            trailing: row.status.capitalized
                        )
                    }
                }
            }
        }
        .task { await load() }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(theme.textPrimary.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func approvalRow(_ row: ApprovalSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.toolName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.textPrimary)
                Text(row.inputPreview).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Button("Approve") {
                Task { await resolve(row, decision: .approveOnce) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
            Button("Deny") {
                Task { await resolve(row, decision: .deny) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(20)
    }

    private func load() async {
        guard let client = makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.approvals()
            pendingRows = response.pending
            historyRows = response.history
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resolve(_ row: ApprovalSummary, decision: ApprovalResolveRequest.Decision) async {
        guard let client = makeClient() else { return }
        do {
            _ = try await client.resolveApproval(
                id: row.id,
                request: ApprovalResolveRequest(decision: decision)
            )
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Tools
// ═══════════════════════════════════════════════════════════════════

struct ToolsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Tools",
            icon: "wrench.and.screwdriver",
            subtitle: "Tool catalog by toolset family"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.metrics.count)", label: "Counters", tint: .cyan)
                StatBadge(
                    value: snapshot.readiness.component(id: "tool.policy")?.detail ?? "Default",
                    label: "Policy",
                    tint: .blue
                )
                StatBadge(
                    value: snapshot.runtimeConfig?.toolPolicy.allowModelToolCalls == true ? "Allowed" : "Blocked",
                    label: "Model calls",
                    tint: snapshot.runtimeConfig?.toolPolicy.allowModelToolCalls == true ? .green : .orange
                )
            }

            PaneCard {
                Text("TOOLSETS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ForEach(toolsetCards, id: \.name) { tc in
                    ListRow(
                        icon: tc.icon,
                        iconTint: tc.color,
                        title: tc.name,
                        subtitle: tc.summary,
                        trailing: "\(tc.count)",
                        trailingTint: theme.textPrimary.opacity(0.7)
                    )
                }
            }

            if let policy = snapshot.runtimeConfig?.toolPolicy {
                PaneCard {
                    Text("POLICY")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(theme.textPrimary.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    ListRow(icon: "number", iconTint: .cyan, title: "Max calls per turn",
                            subtitle: nil, trailing: "\(policy.maxToolCallsPerTurn)")
                    ListRow(icon: "point.3.connected.trianglepath.dotted", iconTint: .cyan,
                            title: "Max chain depth", subtitle: nil, trailing: "\(policy.maxToolChainDepth)")
                    ListRow(icon: "hand.raised", iconTint: policy.allowHumanOnlyFromModel ? .red : .green,
                            title: "Human-only from model",
                            subtitle: nil,
                            trailing: policy.allowHumanOnlyFromModel ? "Allowed" : "Blocked",
                            trailingTint: policy.allowHumanOnlyFromModel ? .red : .green)
                    ListRow(icon: "exclamationmark.triangle",
                            iconTint: policy.allowCriticalToolsFromModel ? .orange : .green,
                            title: "Critical tools from model",
                            subtitle: nil,
                            trailing: policy.allowCriticalToolsFromModel ? "Allowed" : "Blocked",
                            trailingTint: policy.allowCriticalToolsFromModel ? .orange : .green)
                    ListRow(icon: "checkmark.seal", iconTint: .green,
                            title: "Medium-risk approval",
                            subtitle: nil,
                            trailing: policy.requireApprovalForMediumRiskAndAbove ? "Required" : "Optional",
                            trailingTint: policy.requireApprovalForMediumRiskAndAbove ? .green : .orange)
                }
            }
        }
    }

    private struct ToolsetCard {
        let name: String
        let icon: String
        let color: Color
        let summary: String
        let count: Int
    }

    private var toolsetCards: [ToolsetCard] {
        // Render the toolset families with descriptive blurbs.
        // Counts are estimates pulled from metrics when present; otherwise
        // a "—" placeholder. The point of this pane isn't to enumerate
        // every tool — it's to make the registry legible at a glance.
        let metricCount = snapshot.metrics.reduce(into: [String: Int]()) { acc, m in
            acc[m.id] = m.value
        }
        return [
            .init(name: "Core", icon: "circle.hexagongrid",
                  color: .cyan, summary: "Foundational tools: ask, summarize, look up memory.",
                  count: metricCount["tools.core"] ?? 0),
            .init(name: "Memory", icon: "brain.head.profile",
                  color: .purple, summary: "Promote, propose, and audit memory candidates.",
                  count: metricCount["tools.memory"] ?? 0),
            .init(name: "Scout", icon: "binoculars",
                  color: .green, summary: "Personalization scanner — source scan and signal proposal.",
                  count: metricCount["tools.scout"] ?? 0),
            .init(name: "Files", icon: "folder",
                  color: .blue, summary: "Read / write / search files inside the workspace.",
                  count: metricCount["tools.files"] ?? 0),
            .init(name: "Git", icon: "arrow.triangle.branch",
                  color: .orange, summary: "Status, log, diff, branch ops on repositories.",
                  count: metricCount["tools.git"] ?? 0),
            .init(name: "Swift Dev", icon: "swift",
                  color: .red, summary: "Build, test, format, and lint Swift packages.",
                  count: metricCount["tools.swiftDev"] ?? 0),
            .init(name: "EVM", icon: "diamond",
                  color: .indigo, summary: "Ethereum RPC, Uniswap, PancakeSwap skills, transaction build.",
                  count: metricCount["tools.evm"] ?? 0),
            .init(name: "Solana", icon: "sun.max",
                  color: .yellow, summary: "Solana RPC, Jupiter, Pay API wallet, token transfer.",
                  count: metricCount["tools.solana"] ?? 0),
            .init(name: "Launchpads", icon: "flag.checkered",
                  color: .green, summary: "PumpPortal, Bags, Flap, and Four.meme docs and skills.",
                  count: metricCount["tools.launchpads"] ?? 0),
            .init(name: "MCP", icon: "cable.connector",
                  color: .teal, summary: "Registered MCP servers and their exposed tools.",
                  count: metricCount["tools.mcp"] ?? 0),
        ]
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Audit Log
// ═══════════════════════════════════════════════════════════════════

struct AuditLogPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var filter: AuditFilter = .all
    @State private var events: [AuditEventSummary] = []
    @State private var isLoading = false
    @State private var error: String?

    enum AuditFilter: String, CaseIterable, Identifiable {
        case all, success, warning, error
        var id: String { rawValue }
    }

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Audit Log",
            icon: "list.bullet.rectangle",
            subtitle: "Recent agent actions, tool calls, and decisions"
        ) {
            if let error {
                OfflineBanner(reason: error)
            }
            if !snapshot.daemonReachable {
                OfflineBanner(reason: "Daemon offline — audit log fetch failed.")
            }

            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.usage?.chatTurns ?? 0)", label: "Turns", tint: .cyan)
                StatBadge(value: "\(snapshot.usage?.approvedMemoryReferences ?? 0)",
                          label: "Mem refs", tint: .purple)
                StatBadge(
                    value: snapshot.usage?.lastChatAt?.formatted(date: .omitted, time: .shortened) ?? "—",
                    label: "Last chat",
                    tint: .blue
                )
            }

            Picker("Filter", selection: $filter) {
                ForEach(AuditFilter.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)

            PaneCard {
                Text("EVENTS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if filteredEvents.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text(isLoading ? "Loading audit events…" : "No audit events match this filter.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(filteredEvents) { event in
                        ListRow(
                            icon: event.success ? "checkmark.circle.fill" : "xmark.circle.fill",
                            iconTint: event.success ? .green : .red,
                            title: event.toolName ?? event.kind,
                            subtitle: event.detail,
                            trailing: event.timestamp.formatted(date: .omitted, time: .shortened),
                            trailingTint: theme.textPrimary.opacity(0.65)
                        )
                    }
                }
            }
        }
        .task { await load() }
    }

    private var filteredEvents: [AuditEventSummary] {
        switch filter {
        case .all:
            return events
        case .success:
            return events.filter(\.success)
        case .warning:
            return events.filter { $0.success && $0.kind.lowercased().contains("approval") }
        case .error:
            return events.filter { !$0.success }
        }
    }

    private func load() async {
        guard let client = makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.audit()
            events = response.events
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct GoalsDashboardPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    var body: some View {
        DashboardPane(title: "Goals", icon: "target", subtitle: "Goal runner state and iteration progress") {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.records?.goals.count ?? 0)", label: "Goals", tint: .cyan)
                StatBadge(value: activeCount, label: "Active", tint: .green)
            }

            PaneCard {
                Text("GOALS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if let goals = snapshot.records?.goals, !goals.isEmpty {
                    ForEach(goals) { goal in
                        ListRow(
                            icon: goal.state == "completed" ? "checkmark.circle.fill" : "target",
                            iconTint: goal.state == "completed" ? .green : .cyan,
                            title: goal.statement,
                            subtitle: "Progress \(goal.progress)",
                            trailing: goal.state.capitalized
                        )
                    }
                } else {
                    emptyState(icon: "target", text: "No goals recorded yet.")
                }
            }
        }
    }

    private var activeCount: String {
        "\(snapshot.records?.goals.filter { $0.state == "active" || $0.state == "pending" }.count ?? 0)"
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(20)
    }
}

struct ManifestingDashboardPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    var body: some View {
        DashboardPane(title: "Manifesting", icon: "moon.stars", subtitle: "Recent background proposal passes") {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.records?.manifestations.count ?? 0)", label: "Passes", tint: .purple)
                StatBadge(value: "\(proposalCount)", label: "Proposals", tint: .yellow)
            }

            PaneCard {
                Text("RECENT PASSES")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if let rows = snapshot.records?.manifestations, !rows.isEmpty {
                    ForEach(rows) { row in
                        ListRow(
                            icon: row.status == "completed" ? "checkmark.circle.fill" : "moon.stars",
                            iconTint: row.status == "completed" ? .green : .purple,
                            title: row.triggerReason,
                            subtitle: row.summary,
                            trailing: "\(row.proposalCount)"
                        )
                    }
                } else {
                    emptyState(icon: "moon.stars", text: "No manifestation passes recorded yet.")
                }
            }
        }
    }

    private var proposalCount: Int {
        snapshot.records?.manifestations.reduce(0) { $0 + $1.proposalCount } ?? 0
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(20)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Skills
// ═══════════════════════════════════════════════════════════════════

struct SkillsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var search: String = ""

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Skills",
            icon: "star.fill",
            subtitle: "Skill catalog with trust state"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.skills.count)", label: "Promptable", tint: .yellow)
                StatBadge(
                    value: trustCount(of: "promoted"),
                    label: "Promoted",
                    tint: .green
                )
                StatBadge(
                    value: trustCount(of: "draft"),
                    label: "Drafts",
                    tint: .orange
                )
                StatBadge(
                    value: trustCount(of: "reviewed"),
                    label: "Reviewed",
                    tint: .blue
                )
            }

            TextField("Search skills…", text: $search)
                .textFieldStyle(.roundedBorder)

            PaneCard {
                Text("PROMPTABLE SKILLS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if filteredSkills.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "star")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text(search.isEmpty
                                 ? "No promotable skills loaded yet."
                                 : "Nothing matches “\(search)”.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(filteredSkills) { skill in
                        ListRow(
                            icon: trustIcon(skill.trust),
                            iconTint: trustColor(skill.trust),
                            title: skill.title,
                            subtitle: skill.description,
                            trailing: skill.trust.capitalized,
                            trailingTint: trustColor(skill.trust)
                        )
                    }
                }
            }
        }
    }

    private var filteredSkills: [SkillSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return snapshot.skills }
        return snapshot.skills.filter {
            $0.title.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func trustCount(of trust: String) -> String {
        let count = snapshot.skills.filter { $0.trust.lowercased() == trust }.count
        return "\(count)"
    }

    private func trustIcon(_ trust: String) -> String {
        switch trust.lowercased() {
        case "promoted": return "checkmark.seal.fill"
        case "reviewed": return "eye"
        case "draft":    return "pencil"
        case "rejected": return "xmark.circle"
        case "frozen":   return "snowflake"
        default:         return "star"
        }
    }

    private func trustColor(_ trust: String) -> Color {
        switch trust.lowercased() {
        case "promoted": return .green
        case "reviewed": return .blue
        case "draft":    return .orange
        case "rejected": return .red
        case "frozen":   return .cyan
        default:         return .secondary
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Memory Vault
// ═══════════════════════════════════════════════════════════════════

struct MemoryVaultPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var memories: MemoriesResponse?
    @State private var isLoading = false
    @State private var error: String?

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Memory Vault",
            icon: "brain.head.profile",
            subtitle: "Approved, pending, and rejected memories"
        ) {
            if !snapshot.daemonReachable {
                OfflineBanner(reason: "Daemon offline — showing local files only.")
            }

            HStack(spacing: 10) {
                StatBadge(value: "\(memories?.approved.count ?? 0)", label: "Approved", tint: .green)
                StatBadge(value: "\(memories?.pending.count ?? 0)", label: "Pending", tint: .orange)
                StatBadge(value: "\(memories?.rejected.count ?? 0)", label: "Rejected", tint: .red)
                StatBadge(value: "\(snapshot.local.memoryFiles)", label: "Files", tint: .cyan)
            }

            if let pending = memories?.pending, !pending.isEmpty {
                PaneCard {
                    sectionHeader("PENDING — REVIEW")
                    ForEach(pending) { mem in
                        memoryRow(mem)
                    }
                }
            }

            PaneCard {
                sectionHeader("APPROVED")
                if let approved = memories?.approved, !approved.isEmpty {
                    ForEach(approved) { mem in
                        memoryRow(mem)
                    }
                } else {
                    emptyState(icon: "brain", text: isLoading ? "Loading…" : "No approved memories yet.")
                }
            }

            if let rejected = memories?.rejected, !rejected.isEmpty {
                PaneCard {
                    sectionHeader("REJECTED")
                    ForEach(rejected) { mem in
                        memoryRow(mem)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func memoryRow(_ mem: MemorySummary) -> some View {
        ListRow(
            icon: "brain",
            iconTint: sensitivityColor(mem.sensitivity),
            title: mem.text,
            subtitle: "\(mem.category) · \(mem.sensitivity)" + (mem.confidence.map { " · \(Int($0 * 100))%" } ?? ""),
            trailing: mem.status.capitalized,
            trailingTint: statusColor(mem.status)
        )
    }

    private func sensitivityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "high":   return .red
        case "medium": return .orange
        case "low":    return .green
        default:       return .secondary
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "approved": return .green
        case "pending":  return .orange
        case "rejected": return .red
        default:         return .secondary
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(theme.textPrimary.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private func emptyState(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textPrimary.opacity(0.55))
            }
            Spacer()
        }
        .padding(16)
    }

    private func load() async {
        guard let client = makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            memories = try await client.memories()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local Models
// ═══════════════════════════════════════════════════════════════════

struct LocalModelsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    @State private var installed: [InstalledOllamaModel] = []
    @State private var trending: [DynamicModelLoader.TrendingModel] = []
    @State private var hardware: SwooshModels.HardwareProfile = .detectCurrent()
    @State private var pulling: String? = nil
    @State private var pullProgress: String = ""
    @State private var pullError: String? = nil
    @State private var isLoading = false

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        DashboardPane(
            title: "Local Models",
            icon: "cpu",
            subtitle: "On-device inference — runs entirely on your Mac"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: hardware.chip, label: "Chip", tint: .blue)
                StatBadge(value: "\(Int(hardware.totalMemoryGB)) GB", label: "Memory", tint: .cyan)
                StatBadge(value: hardware.maxTier.rawValue.capitalized, label: "Max tier", tint: .purple)
                StatBadge(value: "\(installed.filter(\.isChatCapable).count)", label: "Chat models", tint: .green)
            }

            recommendedDefaultCard

            installedCard

            trendingCard

            providersCard
        }
        .task { await load() }
    }

    @ViewBuilder
    private var recommendedDefaultCard: some View {
        let recommendations = DynamicModelLoader.shared.recommendedLocalModels(hardware: hardware)
        PaneCard {
            sectionHeader("RECOMMENDED PULLS FOR YOUR HARDWARE")
            ForEach(recommendations) { model in
                let isInstalled = installed.contains { $0.name.hasPrefix(model.tag) }
                HStack(spacing: 12) {
                    Image(systemName: isInstalled ? "checkmark.seal.fill" : (model.isDefaultFallback ? "sparkles" : "terminal.fill"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isInstalled ? .green : (model.isDefaultFallback ? .yellow : .cyan))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(model.tag)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                            Text(model.isDefaultFallback ? "DEFAULT" : model.family.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(model.isDefaultFallback ? .yellow : .cyan)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((model.isDefaultFallback ? Color.yellow : Color.cyan).opacity(0.14)))
                            if isInstalled {
                                Text("INSTALLED")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.14)))
                            }
                        }
                        Text("\(model.title) - \(model.reason) ~\(String(format: "%.1f", model.estimatedDiskGB)) GB download.")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.65))
                    }
                    Spacer()
                    if !isInstalled {
                        Button {
                            Task { await pull(model.tag) }
                        } label: {
                            if pulling == model.tag {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Pulling...").font(.system(size: 12, weight: .semibold))
                                }
                            } else {
                                Label("Pull", systemImage: "arrow.down.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(model.isDefaultFallback ? .green : .cyan)
                        .disabled(pulling != nil)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)

                if pulling == model.tag {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                    Text(pullProgress.isEmpty ? "Downloading from Ollama..." : pullProgress)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
            if let pullError {
                Text(pullError).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }

    private var installedCard: some View {
        PaneCard {
            sectionHeader("INSTALLED VIA OLLAMA")
            if isLoading && installed.isEmpty {
                emptyRow(icon: "arrow.clockwise", text: "Querying Ollama…")
            } else if installed.isEmpty {
                emptyRow(icon: "tray", text: "No models installed yet. Use the Pull button above, or run `ollama pull <id>` in a terminal.")
            } else {
                ForEach(installed) { model in
                    ListRow(
                        icon: model.isChatCapable ? "checkmark.circle.fill" : "questionmark.circle",
                        iconTint: model.isChatCapable ? .green : .orange,
                        title: model.name,
                        subtitle: subtitleForInstalled(model),
                        trailing: formatSize(model.sizeBytes),
                        trailingTint: theme.textPrimary.opacity(0.7)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var trendingCard: some View {
        if !trending.isEmpty {
            PaneCard {
                sectionHeader("TRENDING ON HUGGING FACE (live)")
                ForEach(trending.prefix(8)) { model in
                    ListRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconTint: .orange,
                        title: model.id,
                        subtitle: trendingSubtitle(model),
                        trailing: model.downloads.map { formatDownloadCount($0) },
                        trailingTint: theme.textPrimary.opacity(0.65)
                    )
                }
            }
        }
    }

    private var providersCard: some View {
        PaneCard {
            sectionHeader("LOCAL INFERENCE BACKENDS")
            ListRow(
                icon: "apple.logo", iconTint: .purple,
                title: "Apple Foundation Models",
                subtitle: "On-device, free. Set SWOOSH_FOUNDATION_MODEL=1 on swooshd to enable.",
                trailing: snapshot.providers.first(where: { $0.id == ModelDefaults.localFoundationProviderID })?.configured == true ? "On" : "Off",
                trailingTint: snapshot.providers.first(where: { $0.id == ModelDefaults.localFoundationProviderID })?.configured == true ? .green : .secondary
            )
            ListRow(
                icon: "memorychip", iconTint: .blue,
                title: "MLX Local",
                subtitle: "Apple Silicon native inference through mlx-swift-lm.",
                trailing: snapshot.providers.first(where: { $0.id == ModelDefaults.localMLXProviderID })?.configured == true ? "On" : "Off",
                trailingTint: snapshot.providers.first(where: { $0.id == ModelDefaults.localMLXProviderID })?.configured == true ? .green : .secondary
            )
            ListRow(
                icon: "server.rack", iconTint: .teal,
                title: "Ollama",
                subtitle: "127.0.0.1:11434 · \(installed.count) model(s) on disk",
                trailing: installed.isEmpty ? "No models" : "Ready",
                trailingTint: installed.isEmpty ? .orange : .green
            )
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(theme.textPrimary.opacity(0.55))
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    private func emptyRow(icon: String, text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(theme.textPrimary.opacity(0.4))
                Text(text).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(16)
    }

    private func subtitleForInstalled(_ m: InstalledOllamaModel) -> String {
        let parts: [String?] = [
            m.family.map { "Family: \($0)" },
            m.parameterSize,
            m.quantization,
            m.isChatCapable ? nil : "Embedding-only (not chat-capable)"
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func trendingSubtitle(_ m: DynamicModelLoader.TrendingModel) -> String {
        let bits: [String?] = [m.pipelineTag, m.likes.map { "❤ \($0)" }]
        return bits.compactMap { $0 }.joined(separator: " · ")
    }

    private func formatDownloadCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return "\(n / 1_000_000)M ↓"
        case 1_000...:     return "\(n / 1_000)k ↓"
        default:           return "\(n) ↓"
        }
    }

    private func formatSize(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        installed = await DynamicModelLoader.shared.installedOllamaModels()
        trending = await DynamicModelLoader.shared.trendingChatModels(limit: 8)
    }

    @MainActor
    private func pull(_ tag: String) async {
        pulling = tag
        pullError = nil
        defer { pulling = nil }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/pull")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{\"name\":\"\(tag)\",\"stream\":true}".data(using: .utf8)

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                if let data = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let status = obj["status"] as? String ?? ""
                    if let total = obj["total"] as? Int, let completed = obj["completed"] as? Int, total > 0 {
                        pullProgress = "\(status) — \(Int(Double(completed) / Double(total) * 100))%"
                    } else {
                        pullProgress = status
                    }
                }
            }
            await load()
        } catch {
            pullError = error.localizedDescription
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - MCP
// ═══════════════════════════════════════════════════════════════════

struct MCPPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "MCP Servers",
            icon: "cable.connector",
            subtitle: "Model Context Protocol servers and their tools"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.local.mcpFiles)", label: "Configured", tint: .teal)
                StatBadge(value: snapshot.runtimeConfig != nil ? "Yes" : "No",
                          label: "Profile loaded", tint: snapshot.runtimeConfig != nil ? .green : .orange)
            }

            PaneCard {
                Text("PROFILES")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "cable.connector").font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                        Text(snapshot.local.mcpFiles > 0
                             ? "\(snapshot.local.mcpFiles) profile file(s) on disk."
                             : "No MCP servers configured yet.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.55))
                        Text("Add servers via: ~/.swoosh/mcp/servers.json")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textPrimary.opacity(0.45))
                    }
                    Spacer()
                }
                .padding(20)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Plugins
// ═══════════════════════════════════════════════════════════════════

struct PluginsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme
    @State private var plugins: [PluginSummary] = []
    @State private var isLoading = false

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Plugins",
            icon: "puzzlepiece.extension",
            subtitle: "Installed and available plugin manifests"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(plugins.count)", label: "Installed", tint: .indigo)
                StatBadge(value: "\(snapshot.local.pluginFiles)", label: "Files", tint: .teal)
            }

            PaneCard {
                Text("MANIFESTS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if plugins.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "puzzlepiece")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text(isLoading ? "Loading plugins…" : "No plugins installed yet.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(plugins, id: \.id) { plugin in
                        ListRow(
                            icon: plugin.enabled ? "checkmark.circle.fill" : "puzzlepiece",
                            iconTint: plugin.enabled ? .green : theme.textPrimary.opacity(0.55),
                            title: plugin.name,
                            subtitle: "\(plugin.id) · v\(plugin.version)",
                            trailing: plugin.enabled ? "Enabled" : "Disabled",
                            trailingTint: plugin.enabled ? .green : .secondary
                        )
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = makeClient() else { return }
        isLoading = true
        defer { isLoading = false }
        if let response = try? await client.plugins() {
            plugins = response.plugins
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Agents (active goal runner + sessions)
// ═══════════════════════════════════════════════════════════════════

struct AgentsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Agents",
            icon: "person.3.fill",
            subtitle: "Active agent kernel + goal runner"
        ) {
            HStack(spacing: 10) {
                StatBadge(
                    value: snapshot.status?.chat == true ? "Ready" : "Degraded",
                    label: "Kernel",
                    tint: snapshot.status?.chat == true ? .green : .orange
                )
                StatBadge(value: "\(snapshot.status?.chatTurns ?? 0)", label: "Turns", tint: .cyan)
                StatBadge(
                    value: snapshot.status?.lastChatAt?.formatted(date: .omitted, time: .shortened) ?? "—",
                    label: "Last chat",
                    tint: .blue
                )
            }

            PaneCard {
                Text("AGENT KERNEL")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ListRow(icon: "cpu", iconTint: .cyan, title: "Provider",
                        subtitle: snapshot.status?.provider, trailing: snapshot.status?.model)
                ListRow(icon: "clock", iconTint: .blue, title: "Started",
                        subtitle: nil,
                        trailing: snapshot.status?.startedAt.formatted(date: .omitted, time: .shortened))
                ListRow(icon: "brain.head.profile", iconTint: .purple, title: "Memory refs",
                        subtitle: nil,
                        trailing: "\(snapshot.usage?.approvedMemoryReferences ?? 0)")
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Workflows
// ═══════════════════════════════════════════════════════════════════

struct WorkflowsPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Workflows",
            icon: "arrow.triangle.branch",
            subtitle: "SwooshFlow definitions and runs"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.local.workflowDrafts)", label: "Drafts", tint: .orange)
                StatBadge(value: "Replayable", label: "Mode", tint: .green)
            }

            PaneCard {
                emptyMessage(
                    icon: "arrow.triangle.branch",
                    title: snapshot.local.workflowDrafts > 0 ? "\(snapshot.local.workflowDrafts) workflow file(s)" : "No workflows yet",
                    detail: "Workflows live under ~/.swoosh/workflows. Every workflow is dry-runnable and replayable; runs land in the audit ledger automatically."
                )
            }
        }
    }

    private func emptyMessage(icon: String, title: String, detail: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.textPrimary.opacity(0.35))
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textPrimary.opacity(0.75))
                Text(detail).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Spacer()
        }
        .padding(22)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Triggers
// ═══════════════════════════════════════════════════════════════════

struct TriggersPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Triggers",
            icon: "bolt.fill",
            subtitle: "Cron, file, manifest, and message triggers"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.local.cronJobs)", label: "Cron jobs", tint: .orange)
                StatBadge(value: "Scheduler", label: "Cron", tint: .green)
            }

            PaneCard {
                Text("TRIGGER FAMILIES")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ListRow(icon: "clock.arrow.circlepath", iconTint: .orange,
                        title: "Cron",
                        subtitle: "\(snapshot.local.cronJobs) job(s) on disk · ~/.swoosh/cron",
                        trailing: nil)
                ListRow(icon: "doc.text.below.ecg", iconTint: .blue,
                        title: "File watch",
                        subtitle: "Run a workflow when a path under the workspace changes.",
                        trailing: nil)
                ListRow(icon: "sparkles", iconTint: .purple,
                        title: "Manifest",
                        subtitle: "Daily / idle-floor pass mining the audit log for skill + memory proposals.",
                        trailing: nil)
                ListRow(icon: "envelope", iconTint: .cyan,
                        title: "Message",
                        subtitle: "Incoming chat-adapter event triggers a workflow.",
                        trailing: nil)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Firewall
// ═══════════════════════════════════════════════════════════════════

struct FirewallPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Agent Firewall",
            icon: "shield.checkered",
            subtitle: "Permission grants and safety flags"
        ) {
            HStack(spacing: 10) {
                StatBadge(
                    value: snapshot.runtimeConfig?.permissionProfile ?? "—",
                    label: "Profile",
                    tint: .blue
                )
                StatBadge(
                    value: snapshot.runtimeConfig?.localDiagnosticFallback == true ? "On" : "Off",
                    label: "Diagnostic fallback",
                    tint: snapshot.runtimeConfig?.localDiagnosticFallback == true ? .orange : .green
                )
            }

            if let safety = snapshot.runtimeConfig?.safetyConfig {
                PaneCard {
                    Text("SAFETY FLAGS")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(theme.textPrimary.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    safetyRow("Autonomous trading", on: safety.autonomousTradingEnabled, dangerous: true)
                    safetyRow("Human-prompted trading", on: safety.humanPromptedTradingEnabled, dangerous: false)
                    safetyRow("Swap execution", on: safety.swapExecutionEnabled, dangerous: true)
                    safetyRow("Portfolio recommendations", on: safety.portfolioRecommendationsEnabled, dangerous: false)
                    safetyRow("Private-key custody", on: safety.privateKeyCustodyEnabled, dangerous: true)
                    safetyRow("Seed phrase ingestion", on: safety.seedPhraseIngestionEnabled, dangerous: true)
                    safetyRow("Cookie ingestion", on: safety.cookieIngestionEnabled, dangerous: true)
                    safetyRow("Shell → blockchain bridge", on: safety.shellToBlockchainBridgeEnabled, dangerous: true)
                    safetyRow("Model self-approval", on: safety.modelSelfApprovalEnabled, dangerous: true)
                    safetyRow("Mainnet writes by default", on: safety.mainnetWritesByDefault, dangerous: true)
                }
            } else {
                PaneCard {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "shield.slash").font(.system(size: 22))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text("Runtime config not loaded.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(20)
                }
            }
        }
    }

    private func safetyRow(_ title: String, on: Bool, dangerous: Bool) -> some View {
        ListRow(
            icon: on ? "checkmark.circle.fill" : "circle",
            iconTint: on ? (dangerous ? .red : .green) : .secondary,
            title: title,
            subtitle: nil,
            trailing: on ? "Enabled" : "Disabled",
            trailingTint: on ? (dangerous ? .red : .green) : .secondary
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Benchmarks
// ═══════════════════════════════════════════════════════════════════

struct BenchmarksPane: View {
    let snapshot: DashboardRuntimeSnapshot
    @Environment(\.swooshTheme) var theme

    init(snapshot: DashboardRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        DashboardPane(
            title: "Benchmarks",
            icon: "chart.bar.xaxis",
            subtitle: "Performance metrics and regression markers"
        ) {
            HStack(spacing: 10) {
                StatBadge(value: "\(snapshot.metrics.count)", label: "Counters", tint: .cyan)
                StatBadge(
                    value: snapshot.usage?.lastChatAt?.formatted(date: .omitted, time: .shortened) ?? "—",
                    label: "Last sample", tint: .blue
                )
            }

            PaneCard {
                Text("COUNTERS")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                if snapshot.metrics.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.textPrimary.opacity(0.35))
                            Text("No counters reported yet.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.55))
                            Text("Counters arrive once the daemon's metrics endpoint emits samples.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(snapshot.metrics) { metric in
                        ListRow(
                            icon: "number",
                            iconTint: .cyan,
                            title: metric.id,
                            subtitle: nil,
                            trailing: "\(metric.value)"
                        )
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Providers (configure + switch)
// ═══════════════════════════════════════════════════════════════════

/// Real providers page: every provider is a card with status, current
/// model, a "Use this provider" button, and an inline configuration
/// form (API-key paste / ChatGPT sign-in / env-var hint depending on
/// provider type). Replaces the old read-only ProviderStatusPane.
struct ProvidersConfigPane: View {
    @Environment(\.swooshTheme) var theme
    @State private var snapshot: ProvidersResponse?
    @State private var codexAuth: CodexAuthStatus?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        DashboardPane(
            title: "Providers",
            icon: "cloud",
            subtitle: "Switch between cloud subscriptions, local models, and on-device inference"
        ) {
            if let error {
                OfflineBanner(reason: error)
            }

            HStack(spacing: 10) {
                StatBadge(
                    value: "\(snapshot?.providers.count ?? 0)",
                    label: "Configured",
                    tint: .cyan
                )
                StatBadge(
                    value: activeName,
                    label: "Active",
                    tint: .green
                )
                StatBadge(
                    value: "\(healthyCount)",
                    label: "Signed in",
                    tint: .blue
                )
            }

            ForEach(orderedProviders, id: \.id) { provider in
                ProviderConfigCard(
                    provider: provider,
                    isActive: snapshot?.activeProviderID == provider.id,
                    codexAuth: provider.id == "codex" ? codexAuth : nil,
                    onActivate: { await activate(provider.id) },
                    onSaveAPIKey: { key in await saveKey(provider.id, key: key) },
                    onStartCodexLogin: { await startCodex() },
                    onCancelCodexLogin: { await cancelCodex() },
                    onRefresh: { await load() }
                )
            }
        }
        .task { await load() }
    }

    private var activeName: String {
        guard let snap = snapshot,
              let active = snap.activeProviderID,
              let row = snap.providers.first(where: { $0.id == active }) else { return "—" }
        return row.name
    }

    private var healthyCount: Int {
        snapshot?.providers.filter { $0.configured }.count ?? 0
    }

    /// Display order: ChatGPT first (premium subscription path), then API
    /// keys, then local options. Within each group keep priority order.
    private var orderedProviders: [ProviderSummary] {
        guard let snap = snapshot else { return [] }
        let priorityIDs = [
            "codex",
            "openai", "openrouter",
            ModelDefaults.localFoundationProviderID, ModelDefaults.localMLXProviderID, "local-openai",
            "local-diagnostic"
        ]
        var indexed: [(Int, ProviderSummary)] = []
        for provider in snap.providers {
            let rank = priorityIDs.firstIndex(of: provider.id) ?? priorityIDs.count
            indexed.append((rank, provider))
        }
        return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private func load() async {
        guard let client = makeClient() else {
            error = "Daemon offline — pair the iPhone or restart swooshd."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await client.providers()
            snapshot = resp
            if let codex = try? await client.codexAuthStatus() {
                codexAuth = codex
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func activate(_ id: String) async {
        guard let client = makeClient() else { return }
        _ = try? await client.selectProvider(providerID: id)
        await load()
    }

    private func saveKey(_ id: String, key: String) async {
        guard let client = makeClient() else { return }
        _ = try? await client.saveProviderKey(providerID: id, apiKey: key)
        await load()
    }

    private func startCodex() async {
        guard let client = makeClient() else { return }
        codexAuth = try? await client.startCodexAuth()
        // The daemon polls codex login internally; the user finishes
        // in their browser. We poll status until terminal.
        while let st = codexAuth, st.state == .pending {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            codexAuth = try? await client.codexAuthStatus()
        }
        await load()
    }

    private func cancelCodex() async {
        guard let client = makeClient() else { return }
        codexAuth = try? await client.cancelCodexAuth()
    }
}

struct ProviderConfigCard: View {
    @Environment(\.swooshTheme) var theme
    let provider: ProviderSummary
    let isActive: Bool
    let codexAuth: CodexAuthStatus?
    let onActivate: () async -> Void
    let onSaveAPIKey: (String) async -> Void
    let onStartCodexLogin: () async -> Void
    let onCancelCodexLogin: () async -> Void
    let onRefresh: () async -> Void

    @State private var draftKey: String = ""
    @State private var showKeyField = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusRow
            actionRow
            if showKeyField {
                apiKeyField
            }
            if provider.id == "codex" {
                codexFooter
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? theme.accent.opacity(0.06) : theme.textPrimary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isActive ? theme.accent.opacity(0.4) : theme.textPrimary.opacity(0.08),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(providerColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: providerIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(providerColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.green.opacity(0.32), lineWidth: 0.5))
                    }
                }
                Text(blurb)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.62))
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(costLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(costTint)
                Text(locationLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.5))
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            if let model = provider.model, !model.isEmpty {
                Text(model)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(theme.textPrimary.opacity(0.06))
                    )
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            if !provider.configured {
                if provider.id == "codex" {
                    Button {
                        Task { busy = true; await onStartCodexLogin(); busy = false }
                    } label: {
                        Label(busy ? "Opening browser…" : "Sign in with ChatGPT",
                              systemImage: "person.badge.key.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                    .disabled(busy)
                } else if acceptsAPIKey {
                    Button {
                        withAnimation { showKeyField.toggle() }
                    } label: {
                        Label(showKeyField ? "Hide key field" : "Add API key", systemImage: "key.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if provider.id == ModelDefaults.localFoundationProviderID {
                    InfoChip(text: "Set SWOOSH_FOUNDATION_MODEL=1 on the daemon and restart.")
                } else if provider.id == ModelDefaults.localMLXProviderID {
                    InfoChip(text: "Runs Gemma 4/Qwen through mlx-swift-lm on Apple Silicon.")
                } else if provider.id == "local-openai" {
                    InfoChip(text: "Run a local Ollama server on 127.0.0.1:11434.")
                }
            }

            Spacer(minLength: 8)

            if !isActive {
                Button {
                    Task { busy = true; await onActivate(); busy = false }
                } label: {
                    Label(busy ? "Switching…" : "Use this provider", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(busy || !provider.configured)
            }
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("Paste API key (sk-…)", text: $draftKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showKeyField = false; draftKey = "" }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Save key") {
                    let k = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty else { return }
                    Task {
                        busy = true
                        await onSaveAPIKey(k)
                        busy = false
                        showKeyField = false
                        draftKey = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            Text("Stored in the Mac Keychain under service `ai.swoosh.agent`. The agent will route through this provider on the next daemon restart.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.55))
        }
    }

    @ViewBuilder
    private var codexFooter: some View {
        if let auth = codexAuth, auth.state == .pending {
            VStack(alignment: .leading, spacing: 6) {
                Divider().opacity(0.2)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for browser auth…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button("Cancel") {
                        Task { await onCancelCodexLogin() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                if let url = auth.url {
                    Text(url)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        } else if let auth = codexAuth, auth.state == .failed, let msg = auth.message {
            Divider().opacity(0.2)
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.7))
            }
        }
    }

    // MARK: Visual mappings

    private var acceptsAPIKey: Bool {
        ["openai", "openrouter"].contains(provider.id)
    }

    private var providerIcon: String {
        switch provider.id {
        case "codex":            return "sparkles"
        case "openai":           return "circle.hexagongrid"
        case "openrouter":       return "arrow.triangle.branch"
        case ModelDefaults.localFoundationProviderID: return "apple.logo"
        case ModelDefaults.localMLXProviderID:        return "memorychip"
        case "local-openai":     return "server.rack"
        case "local-diagnostic": return "stethoscope"
        default:                 return "cloud"
        }
    }

    private var providerColor: Color {
        switch provider.id {
        case "codex":            return .green
        case "openai":           return .indigo
        case "openrouter":       return .orange
        case ModelDefaults.localFoundationProviderID: return .purple
        case ModelDefaults.localMLXProviderID:        return .blue
        case "local-openai":     return .teal
        case "local-diagnostic": return .gray
        default:                 return .secondary
        }
    }

    private var blurb: String {
        switch provider.id {
        case "codex":            return "Uses your ChatGPT Plus / Pro subscription via the local Codex CLI. No API key."
        case "openai":           return "Direct OpenAI Platform API. Paste sk-… to enable GPT-5.x."
        case "openrouter":       return "Routed access to many model providers under one API."
        case ModelDefaults.localFoundationProviderID: return "Apple's on-device Foundation Models. Free, private."
        case ModelDefaults.localMLXProviderID:        return "MLX Swift inference on Apple Silicon with Gemma 4/Qwen hub models."
        case "local-openai":     return "Local OpenAI-compatible servers like Ollama or LM Studio."
        case "local-diagnostic": return "Deterministic fallback used when no provider is configured."
        default:                 return "External provider."
        }
    }

    private var costLabel: String {
        switch provider.id {
        case "codex":            return "ChatGPT Plus"
        case "openai":           return "Paid"
        case "openrouter":       return "Paid"
        case ModelDefaults.localFoundationProviderID: return "Free"
        case ModelDefaults.localMLXProviderID:        return "Free"
        case "local-openai":     return "Free"
        default:                 return "—"
        }
    }

    private var costTint: Color {
        switch provider.id {
        case "codex":            return .green
        case "openai", "openrouter": return .orange
        default:                 return .secondary
        }
    }

    private var locationLabel: String {
        switch provider.id {
        case "codex", "openai", "openrouter": return "Cloud"
        default: return "Local"
        }
    }

    private var statusColor: Color {
        if isActive { return .green }
        if provider.configured { return .blue }
        return .orange
    }

    private var statusLabel: String {
        switch provider.status {
        case "signed_in":             return "Signed in"
        case "configured":            return "API key configured"
        case "missing_key":           return "API key required"
        case "needs_signin":          return "Sign in to ChatGPT"
        case "running":               return "Running"
        case "available":             return "Available"
        case "not_running":           return "Not running"
        case "active_until_model_provider_configured":
            return "Fallback (diagnostic)"
        default:
            return provider.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct InfoChip: View {
    @Environment(\.swooshTheme) var theme
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.55))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.7))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.textPrimary.opacity(0.05))
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared client builder
// ═══════════════════════════════════════════════════════════════════

private func makeClient() -> SwooshAPIClient? {
    SwooshDaemonClient.client()
}

#endif
