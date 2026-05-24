// SwooshUI/DashboardPanes/FirewallBenchmarksPanes.swift — Firewall and benchmark dashboard panes — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

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

#endif
