// Apps/SwooshiOS/WalletView.swift — Wallet analytics surface backed by swooshd

import SwiftUI
import SwooshClient

struct WalletView: View {
    @Environment(ClientSession.self) private var session
    @State private var dashboard: WalletDashboardResponse?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if session.isPaired {
                paired
            } else {
                unpaired
            }
        }
        .task(id: session.host?.absoluteString) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var paired: some View {
        Form {
            Section("Wallet") {
                if let dashboard {
                    LabeledContent("Status", value: dashboard.connected ? "Bridge available" : "No wallet connected")
                    if let walletLabel = dashboard.walletLabel {
                        LabeledContent("Source", value: walletLabel)
                    }
                } else {
                    placeholder("Wallet dashboard has not loaded.")
                }
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing wallet state")
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let dashboard {
                Section("Analytics") {
                    WalletMetricRow(title: "Total value", value: dashboard.analytics.totalValueUSD)
                    WalletMetricRow(title: "Realized PnL", value: dashboard.analytics.realizedPnLUSD)
                    WalletMetricRow(title: "Unrealized PnL", value: dashboard.analytics.unrealizedPnLUSD)
                    WalletMetricRow(title: "Total PnL", value: dashboard.analytics.totalPnLPercent)
                    WalletMetricRow(title: "Daily change", value: dashboard.analytics.dailyChangePercent)
                    LabeledContent("Open positions", value: "\(dashboard.analytics.openPositions)")
                }

                Section("Assets") {
                    if dashboard.assets.isEmpty {
                        placeholder("No live balances yet. Connect a wallet or account source to populate portfolio rows.")
                    } else {
                        ForEach(dashboard.assets) { asset in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(asset.symbol)
                                        .font(.headline)
                                    Spacer()
                                    Text(asset.valueUSD ?? "Not priced")
                                        .foregroundStyle(asset.valueUSD == nil ? .secondary : .primary)
                                }
                                Text("\(asset.quantity) on \(asset.chain)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let pnl = asset.pnlUSD {
                                    Text("PnL \(pnl) \(asset.pnlPercent ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section("AI insights") {
                    ForEach(dashboard.insights) { insight in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: insight.severity.systemImage)
                                .foregroundStyle(insight.severity.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.headline)
                                Text(insight.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text(insight.source)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section("Trading") {
                    ForEach(dashboard.capabilities) { capability in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(capability.name, systemImage: capability.iconName)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: capability.enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(capability.enabled ? .green : .secondary)
                            }
                            HStack(spacing: 8) {
                                Text(capability.configured ? "Configured" : "Needs setup")
                                Text(capability.risk)
                                Text(capability.status)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    private var unpaired: some View {
        ContentUnavailableView {
            Label("Not paired", systemImage: "link.badge.plus")
        } description: {
            Text("Pair this phone with swooshd in Settings before opening wallet analytics.")
        }
    }

    private func load() async {
        guard session.isPaired, let client = session.client() else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            dashboard = try await client.walletDashboard()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct WalletMetricRow: View {
    let title: String
    let value: String?

    var body: some View {
        LabeledContent(title) {
            Text(value ?? "Not available")
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
    }
}

private extension WalletInsightSeverity {
    var systemImage: String {
        switch self {
        case .info: "lightbulb"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

private extension WalletTradingCapabilitySummary {
    var iconName: String {
        switch id {
        case "wallet.bridge": "wallet.pass"
        case "evm.read": "e.circle"
        case "solana.read": "s.circle"
        case "trading.human_prompted": "person.crop.circle.badge.checkmark"
        case "mainnet.write": "network.badge.shield.half.filled"
        case "jupiter.swaps": "arrow.triangle.swap"
        case "uniswap.swaps": "arrow.2.squarepath"
        case "hyperliquid.market_data": "chart.line.uptrend.xyaxis"
        case "hyperliquid.trading": "bolt.horizontal.circle"
        case "portfolio.insights": "brain.head.profile"
        default: "checklist"
        }
    }
}
