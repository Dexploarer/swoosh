// SwooshUI/DashboardPanes/RuntimeInventoryPanes.swift — MCP plugin agent workflow and trigger panes — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

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

#endif
