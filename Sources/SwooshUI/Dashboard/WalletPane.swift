// SwooshUI/Dashboard/WalletPane.swift — Live wallet dashboard — 0.9X
//
// Calls walletDashboard() on the daemon for REAL data.
// Shows connected state, balances, assets, PnL. Not a capability showcase.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct WalletPane: View {
    @State private var dashboard: WalletDashboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    loadingState
                } else if let error = errorMessage {
                    errorState(error)
                } else if let dash = dashboard {
                    if dash.connected {
                        connectedDashboard(dash)
                    } else {
                        disconnectedState
                    }
                } else {
                    disconnectedState
                }
            }
            .padding(24)
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await load() }
    }

    // ── Loading ──────────────────────────────────────────────────

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading wallet…")
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // ── Error ────────────────────────────────────────────────────

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(VoltPaper.destructive.opacity(0.5))
            Text("Daemon Unreachable")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .multilineTextAlignment(.center)
            retryButton
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // ── Disconnected (daemon up but no wallet) ───────────────────

    private var disconnectedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "wallet.bifold")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.3))
            Text("No Wallet Connected")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            Text("Create or import a wallet to view balances, assets, and trading capabilities.")
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Supported chains
            HStack(spacing: 16) {
                chainCard("Solana", icon: "s.circle.fill", color: VoltPaper.Chart.c1)
                chainCard("Ethereum", icon: "e.circle.fill", color: VoltPaper.Chart.c3)
                chainCard("BNB Chain", icon: "b.circle.fill", color: VoltPaper.Chart.c4)
            }
            .padding(.top, 8)

            HStack(spacing: 12) {
                actionButton("Create Wallet", icon: "plus", color: SwooshNeonTokens.Accent.cyan)
                actionButton("Import Wallet", icon: "square.and.arrow.down", color: VoltPaper.accent)
            }
            .padding(.top, 4)

            retryButton
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // ── Connected dashboard ──────────────────────────────────────

    @ViewBuilder
    private func connectedDashboard(_ dash: WalletDashboardResponse) -> some View {
        // Header
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Wallet")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    HStack(spacing: 4) {
                        Circle().fill(VoltPaper.accent).frame(width: 7, height: 7)
                            .shadow(color: VoltPaper.accent.opacity(0.5), radius: 3)
                        Text("Connected")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(VoltPaper.accent)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VoltPaper.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                if let label = dash.walletLabel {
                    Text(label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
            }
            Spacer()
            Button { Task { await load() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .buttonStyle(.plain)
        }

        // Total value
        if let total = dash.analytics.totalValueUSD {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Value")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text("$\(total)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                if let daily = dash.analytics.dailyChangePercent {
                    let isPositive = !daily.hasPrefix("-")
                    HStack(spacing: 4) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10))
                        Text("\(daily)% today")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(isPositive ? VoltPaper.accent : VoltPaper.destructive)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VoltPaper.foreground.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
            )
        }

        // Analytics cards
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ], spacing: 10) {
            analyticCard("Realized P&L", value: dash.analytics.realizedPnLUSD, prefix: "$")
            analyticCard("Unrealized P&L", value: dash.analytics.unrealizedPnLUSD, prefix: "$")
            analyticCard("Total P&L", value: dash.analytics.totalPnLPercent, suffix: "%")
            analyticCard("Open Positions", value: "\(dash.analytics.openPositions)")
        }

        // Asset table
        if !dash.assets.isEmpty {
            assetTable(dash.assets)
        }

        // Insights
        if !dash.insights.isEmpty {
            insightsSection(dash.insights)
        }
    }

    // ── Analytics card ───────────────────────────────────────────

    private func analyticCard(_ label: String, value: String?, prefix: String = "", suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            if let v = value {
                let isNeg = v.hasPrefix("-")
                Text("\(prefix)\(v)\(suffix)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(isNeg ? VoltPaper.destructive : SwooshNeonTokens.Canvas.text1)
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VoltPaper.foreground.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    private func analyticCard(_ label: String, value: String) -> some View {
        analyticCard(label, value: Optional(value))
    }

    // ── Asset table ──────────────────────────────────────────────

    private func assetTable(_ assets: [WalletAssetSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                Text("Holdings (\(assets.count))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }

            // Column headers
            HStack(spacing: 0) {
                Text("Asset").frame(width: 140, alignment: .leading)
                Text("Chain").frame(width: 70, alignment: .leading)
                Text("Qty").frame(width: 100, alignment: .trailing)
                Text("Value").frame(width: 90, alignment: .trailing)
                Text("P&L").frame(width: 80, alignment: .trailing)
                Text("P&L%").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            .padding(.horizontal, 10)

            Rectangle().fill(SwooshNeonTokens.Line.rule).frame(height: 0.5)

            ForEach(assets) { asset in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(asset.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        if let name = asset.name {
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 140, alignment: .leading)

                    Text(asset.chain)
                        .font(.system(size: 10))
                        .foregroundStyle(chainColorForAsset(asset.chain))
                        .frame(width: 70, alignment: .leading)

                    Text(asset.quantity)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                        .frame(width: 100, alignment: .trailing)

                    Text(asset.valueUSD.map { "$\($0)" } ?? "—")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        .frame(width: 90, alignment: .trailing)

                    pnlText(asset.pnlUSD, prefix: "$")
                        .frame(width: 80, alignment: .trailing)

                    pnlText(asset.pnlPercent, suffix: "%")
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VoltPaper.foreground.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    // ── Insights ─────────────────────────────────────────────────

    private func insightsSection(_ insights: [WalletInsightSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(VoltPaper.Chart.c4)
                Text("Insights (\(insights.count))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            }

            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(severityColor(insight.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        Text(insight.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                }
                .padding(10)
                .background(severityColor(insight.severity).opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // ── Small helpers ─────────────────────────────────────────────

    @ViewBuilder
    private func pnlText(_ value: String?, prefix: String = "", suffix: String = "") -> some View {
        if let v = value {
            let isNeg = v.hasPrefix("-")
            Text("\(prefix)\(v)\(suffix)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(isNeg ? VoltPaper.destructive : VoltPaper.accent)
        } else {
            Text("—")
                .font(.system(size: 10))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
    }

    private func chainCard(_ name: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
        }
        .padding(12)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func actionButton(_ label: String, icon: String, color: Color) -> some View {
        Button {} label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(VoltPaper.foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(color.gradient)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var retryButton: some View {
        Button { Task { await load() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(VoltPaper.foreground.opacity(0.04))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func severityColor(_ severity: WalletInsightSeverity) -> Color {
        switch severity {
        case .info: return SwooshNeonTokens.Accent.cyan
        case .warning: return VoltPaper.Chart.c4
        case .critical: return VoltPaper.destructive
        }
    }

    private func chainColorForAsset(_ chain: String) -> Color {
        switch chain.lowercased() {
        case "solana", "sol": return VoltPaper.Chart.c1
        case "ethereum", "eth": return VoltPaper.Chart.c3
        case "bnb", "bsc", "bnb chain": return VoltPaper.Chart.c4
        default: return VoltPaper.mutedFg
        }
    }

    // ── Network ──────────────────────────────────────────────────

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Cannot connect to Swoosh daemon. Make sure the app is running."
            return
        }
        do {
            dashboard = try await client.walletDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif
