// SwooshUI/DashboardPanes/ToolAuditDashboardPanes.swift — Tools and audit dashboard panes — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

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

#endif
