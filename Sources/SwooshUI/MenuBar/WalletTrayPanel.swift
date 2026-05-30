// SwooshUI/MenuBar/WalletTrayPanel.swift — 0.1A Wallet summary panel
//
// Glanceable wallet summary for the menu-bar tray. Reads the same daemon
// RPC the full WalletPane uses (`SwooshDaemonClient` →
// `SwooshAPIClient.walletDashboard()`): total value, daily change, open
// positions, and the top holdings. Green accent (funds / value). Never
// touches keys or seed phrases — read-only display over the RPC boundary.
// "Open in Detour" jumps to the full wallet surface.

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshGenerativeUI

struct WalletTrayPanel: View {
    @State private var dashboard: WalletDashboardResponse?
    @State private var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        TrayPanelScaffold(
            title: "Wallet",
            subtitle: "Balances & positions",
            icon: "banknote.fill",
            accent: .green,
            openTab: "wallet"
        ) {
            switch phase {
            case .loading:
                TrayStatusRow(icon: "banknote", message: "Loading wallet…", accent: .green, spinning: true)
            case .failed(let msg):
                TrayStatusRow(icon: "exclamationmark.triangle.fill", message: msg, accent: .green)
            case .loaded:
                if let dashboard, dashboard.connected {
                    connected(dashboard)
                } else {
                    TrayStatusRow(icon: "banknote", message: "No wallet connected. Open Detour to set one up.", accent: .green)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Connected

    private func connected(_ d: WalletDashboardResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            headline(d)
            if !d.assets.isEmpty {
                WalletTrayChart(assets: d.assets)
                assets(d.assets)
            }
        }
    }

    private func headline(_ d: WalletDashboardResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = d.walletLabel {
                TraySectionLabel(text: label)
            }
            Text(d.analytics.totalValueUSD.map { "$\($0)" } ?? "—")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            HStack(spacing: 12) {
                if let change = d.analytics.dailyChangePercent {
                    pill(icon: changeIcon(change), text: "\(change)%", accent: changeAccent(change))
                }
                pill(icon: "chart.line.uptrend.xyaxis", text: "\(d.analytics.openPositions) open", accent: .green)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(.green, state: .focus, shape: .card)
    }

    private func assets(_ all: [WalletAssetSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TraySectionLabel(text: "Top holdings")
            ForEach(all.prefix(4)) { asset in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(asset.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Text(asset.chain)
                            .font(.system(size: 9.5))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(asset.valueUSD.map { "$\($0)" } ?? asset.quantity)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        if let pnl = asset.pnlPercent {
                            Text("\(pnl)%")
                                .font(.system(size: 9.5))
                                .foregroundStyle(changeAccent(pnl).color)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 11)
                .neonTile(.green, state: .idle, shape: .card)
            }
        }
    }

    private func pill(icon: String, text: String, accent: NeonAccent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(accent.color)
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .overlay(
            Capsule().strokeBorder(accent.color.opacity(SwooshNeonTokens.Line.dim),
                                   lineWidth: SwooshNeonTokens.Line.width)
        )
    }

    private func changeIcon(_ pct: String) -> String {
        pct.hasPrefix("-") ? "arrow.down.right" : "arrow.up.right"
    }

    private func changeAccent(_ pct: String) -> NeonAccent {
        pct.hasPrefix("-") ? .gold : .green
    }

    // MARK: - Data

    private func load() async {
        phase = .loading
        guard let client = SwooshDaemonClient.client() else {
            phase = .failed("Detour runtime offline.")
            return
        }
        do {
            dashboard = try await client.walletDashboard()
            phase = .loaded
        } catch {
            phase = .failed("Couldn't load wallet.")
        }
    }
}

#endif
