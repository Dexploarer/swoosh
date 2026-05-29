// SwooshUI/MenuBar/CloudTrayPanel.swift — 0.2A Detour Cloud panel
//
// Tray surface for *Detour Cloud* — the hosted side of Detour (account +
// cloud-run agents), NOT a model-provider switcher (provider routing lives
// in the dashboard's Models surface). Shows the one real signal available
// today — whether this Mac's in-process runtime is online — and honest
// "coming soon" cards for the Detour Cloud account and cloud agents. Gold
// accent (energy / throughput). The local-runtime check uses the existing
// SwooshDaemonClient health probe; no new backend.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

struct CloudTrayPanel: View {
    @State private var runtimeOnline: Bool?

    var body: some View {
        TrayPanelScaffold(
            title: "Detour Cloud",
            subtitle: "Account & cloud agents",
            icon: "cloud.fill",
            accent: .gold
        ) {
            VStack(alignment: .leading, spacing: 14) {
                runtimeSection
                accountSection
                cloudAgentsSection
            }
        }
        .task { runtimeOnline = await SwooshDaemonClient.health() }
    }

    // MARK: - Local runtime (real signal)

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TraySectionLabel(text: "This Mac")
            HStack(spacing: 10) {
                Circle()
                    .fill(runtimeColor)
                    .frame(width: 7, height: 7)
                    .neonGlow(runtimeOnline == true ? .green : .gold,
                              intensity: SwooshNeonTokens.Glow.focus)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Local runtime")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    Text(runtimeLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .neonTile(.gold, state: .idle, shape: .card)
        }
    }

    private var runtimeColor: Color {
        switch runtimeOnline {
        case .some(true): return NeonAccent.green.color
        case .some(false): return NeonAccent.gold.color
        case .none: return SwooshNeonTokens.Canvas.text3
        }
    }

    private var runtimeLabel: String {
        switch runtimeOnline {
        case .some(true): return "Online — agent running on this Mac"
        case .some(false): return "Offline"
        case .none: return "Checking…"
        }
    }

    // MARK: - Detour Cloud account (future)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TraySectionLabel(text: "Account")
            infoCard(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "Not connected",
                detail: "Sign in to Detour Cloud to sync agents, memories, and goals across your devices."
            )
        }
    }

    // MARK: - Cloud agents (future)

    private var cloudAgentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TraySectionLabel(text: "Cloud Agents")
            infoCard(
                icon: "sparkles",
                title: "Coming soon",
                detail: "Run Detour agents in the cloud — long-horizon goals and scheduled work that keep going while your Mac sleeps."
            )
        }
    }

    private func infoCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NeonAccent.gold.color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Spacer(minLength: 0)
            }
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(.gold, state: .idle, shape: .card)
    }
}

#endif
