// DetourHomeCryptoPanel.swift — social and on-chain command center (0.5A)

import SwiftUI

struct DetourHomeCryptoPanel: View {
    @ObservedObject var wallet: DetourHomeWalletModel
    let socialItems: [DetourSetupInsightItem]
    let reviewSetup: () -> Void
    let applySetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let dashboard = wallet.dashboard {
                metrics(dashboard)
                HStack(alignment: .top, spacing: 14) {
                    DetourWalletBarChart(
                        title: "Portfolio by chain",
                        emptyText: "No wallet accounts yet.",
                        points: wallet.chainPoints
                    )
                    DetourWalletBarChart(
                        title: "Trading readiness",
                        emptyText: "Wallet checks have not reported capability state yet.",
                        points: wallet.capabilityPoints
                    )
                }
                HStack(alignment: .top, spacing: 14) {
                    assets(dashboard.assets)
                    capabilities(wallet.highlightedCapabilities)
                }
            } else {
                emptyWalletState
            }
            socialState
            socialConnectorGrid
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "network")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.blue, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("Social and on-chain command center")
                    .font(.title3.weight(.semibold))
                Text("Detour can pair relationship context with Solana, BNB Chain, EVM, Hyperliquid, launchpad, and wallet tools when they pass live checks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                DetourHomeStatusBadge(label: wallet.state.label, tint: wallet.dashboard == nil ? .orange : .green)
                Button {
                    wallet.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
    }

    private func metrics(_ dashboard: WalletDashboardResponse) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
            DetourHomeMiniMetric(
                title: "Wallet",
                value: dashboard.connected ? "Connected" : "Not connected",
                detail: dashboard.walletLabel ?? "Local wallet bridge"
            )
            DetourHomeMiniMetric(
                title: "Assets",
                value: "\(dashboard.assets.count)",
                detail: "tracked wallet entries"
            )
            DetourHomeMiniMetric(
                title: "Positions",
                value: "\(dashboard.analytics.openPositions)",
                detail: "open positions reported"
            )
            DetourHomeMiniMetric(
                title: "Alerts",
                value: "\(dashboard.insights.count)",
                detail: "wallet doctor notes"
            )
        }
    }

    private var emptyWalletState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet status is not loaded.")
                .font(.headline)
            Text(walletFailureText)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Check wallet") {
                    wallet.refresh()
                }
                .buttonStyle(.borderedProminent)
                Button("Review setup") {
                    reviewSetup()
                }
                .buttonStyle(.bordered)
                Button("Connect social") {
                    applySetup()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var walletFailureText: String {
        if case .failed(let message) = wallet.state {
            return message
        }
        return "Detour will read the local daemon wallet dashboard when swooshd is reachable."
    }

    private func assets(_ assets: [WalletAssetSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wallets")
                .font(.headline)
            if assets.isEmpty {
                Text("Create or connect a Solana, BNB Chain, Base, or Ethereum wallet to show balances here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assets.prefix(5)) { asset in
                    HStack(spacing: 10) {
                        DetourHomeChainDot(chain: asset.chain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.name ?? asset.symbol)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text("\(asset.quantity) · \(displayChain(asset.chain))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func capabilities(_ capabilities: [WalletTradingCapabilitySummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On-chain tools")
                .font(.headline)
            ForEach(capabilities) { capability in
                HStack(spacing: 10) {
                    Circle()
                        .fill(capabilityColor(capability))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capability.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(capabilityStatus(capability))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var socialState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Social surface")
                    .font(.headline)
                Spacer()
                Text("\(readySocialCount) ready of \(socialItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if socialItems.isEmpty {
                Text("Review setup to connect Discord, Telegram, iMessage, X, AgentMail, and relationship context.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(socialItems.prefix(6)) { item in
                        DetourSocialChip(item: item)
                    }
                    if socialItems.count > 6 {
                        Text("+\(socialItems.count - 6)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var socialConnectorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
            ForEach(socialConnectors) { connector in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: connector.systemImage)
                            .foregroundStyle(connector.tint)
                        Spacer()
                        DetourHomeStatusBadge(label: connector.status, tint: connector.tint)
                    }
                    Text(connector.name)
                        .font(.headline)
                    Text(connector.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack {
                        Button(connector.ready ? "Test" : "Set up") {
                            connector.ready ? applySetup() : reviewSetup()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var socialConnectors: [DetourSocialConnectorSummary] {
        [
            connectorSummary(name: "Discord", keys: ["discord"], icon: "bubble.left.and.bubble.right.fill"),
            connectorSummary(name: "Telegram", keys: ["telegram"], icon: "paperplane.fill"),
            connectorSummary(name: "X", keys: ["connector.x", "x account", "x session", "twitter"], icon: "at"),
            connectorSummary(name: "iMessage", keys: ["imessage", "messages"], icon: "message.fill"),
            connectorSummary(name: "AgentMail", keys: ["agentmail", "email"], icon: "envelope.fill"),
        ]
    }

    private func connectorSummary(name: String, keys: [String], icon: String) -> DetourSocialConnectorSummary {
        let item = socialItems.first { item in
            let text = [item.id, item.title, item.subtitle ?? "", item.detail, item.sourceLabel ?? ""]
                .joined(separator: " ")
                .lowercased()
            return keys.contains { text.contains($0) }
        }
        guard let item else {
            return DetourSocialConnectorSummary(
                name: name,
                status: "Set up",
                detail: "Not selected yet. Review setup to add \(name) and any needed access.",
                systemImage: icon,
                tint: .orange,
                ready: false
            )
        }
        let ready = [.selected, .using, .verified].contains(item.status)
        return DetourSocialConnectorSummary(
            name: name,
            status: socialStatusLabel(item.status),
            detail: item.subtitle ?? item.detail,
            systemImage: icon,
            tint: ready ? .green : .orange,
            ready: ready
        )
    }

    private var readySocialCount: Int {
        socialItems.filter { [.selected, .using, .verified].contains($0.status) }.count
    }

    private func capabilityStatus(_ capability: WalletTradingCapabilitySummary) -> String {
        if capability.enabled && capability.configured {
            return "Ready through the agent runtime"
        }
        if capability.enabled {
            return plainStatus(capability.status)
        }
        return "Not enabled"
    }

    private func capabilityColor(_ capability: WalletTradingCapabilitySummary) -> Color {
        if capability.enabled && capability.configured { return .green }
        if capability.enabled { return .orange }
        return .secondary
    }

    private func plainStatus(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ")
    }

    private func displayChain(_ chain: String) -> String {
        switch chain.lowercased() {
        case "solana":
            "Solana"
        case "bnb":
            "BNB Chain"
        case "ethereum":
            "Ethereum"
        case "base":
            "Base"
        default:
            chain
        }
    }

    private func socialStatusLabel(_ status: DetourSetupInsightStatus) -> String {
        switch status {
        case .verified, .using:
            "Connected"
        case .selected:
            "Ready to test"
        default:
            status.label
        }
    }
}

private struct DetourSocialConnectorSummary: Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let detail: String
    let systemImage: String
    let tint: Color
    let ready: Bool
}
