// SwooshUI/Dashboard/WalletPane.swift — Live wallet dashboard — 0.9Y
//
// Calls walletDashboard() on the daemon for REAL data. Shows connected state,
// balances, assets, PnL. Create-wallet flow posts to /api/wallet/accounts.
// Leaf renderers live in WalletPane+Connected.swift (LOC seam).

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct WalletPane: View {
    @State private var dashboard: WalletDashboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var isCreating = false
    @State private var createError: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    loadingState
                } else if let error = errorMessage {
                    errorState(error)
                } else if let dash = dashboard, dash.connected {
                    connectedDashboard(dash)
                } else {
                    disconnectedState
                }
            }
            .padding(24)
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await load() }
        .sheet(isPresented: $showCreateSheet) {
            WalletCreateSheet(
                isCreating: isCreating,
                errorMessage: createError,
                onCreate: { chain, label in Task { await createWallet(chain: chain, label: label) } },
                onCancel: { showCreateSheet = false; createError = nil }
            )
        }
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
            Text("Create a wallet to view balances, assets, and trading capabilities.")
                .font(.system(size: 13))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 16) {
                chainCard("Solana", icon: "s.circle.fill", color: VoltPaper.Chart.c1)
                chainCard("Ethereum", icon: "e.circle.fill", color: VoltPaper.Chart.c3)
                chainCard("BNB Chain", icon: "b.circle.fill", color: VoltPaper.Chart.c4)
            }
            .padding(.top, 8)

            actionButton("Create Wallet", icon: "plus", color: SwooshNeonTokens.Accent.cyan) {
                createError = nil
                showCreateSheet = true
            }
            .padding(.top, 4)

            retryButton
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // ── Connected dashboard ──────────────────────────────────────

    @ViewBuilder
    func connectedDashboard(_ dash: WalletDashboardResponse) -> some View {
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
            Button { createError = nil; showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoltPaper.accent)
            }
            .buttonStyle(.plain)
            .help("Add wallet")
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

    // ── Buttons ──────────────────────────────────────────────────

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

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private func createWallet(chain: String, label: String) async {
        guard let client = SwooshDaemonClient.client() else {
            createError = "Daemon not reachable."
            return
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let finalLabel = trimmed.isEmpty ? "\(chain.capitalized) wallet" : trimmed
        do {
            _ = try await client.createWalletAccount(
                WalletCreateAccountRequest(chain: chain, label: finalLabel)
            )
            showCreateSheet = false
            await load()
        } catch {
            createError = error.localizedDescription
        }
    }
}

#endif
