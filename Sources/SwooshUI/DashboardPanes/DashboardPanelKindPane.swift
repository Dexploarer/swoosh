// SwooshUI/DashboardPanes/DashboardPanelKindPane.swift — Panel-kind and generative UI dashboard panes — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

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

#endif
