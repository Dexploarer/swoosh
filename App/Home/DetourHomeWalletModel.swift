// DetourHomeWalletModel.swift — wallet dashboard state for Detour home (0.5A)

import Combine
import Foundation

@MainActor
final class DetourHomeWalletModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Not checked"
            case .loading:
                "Checking"
            case .loaded:
                "Live"
            case .failed:
                "Offline"
            }
        }
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var dashboard: WalletDashboardResponse?

    var baseURL: URL {
        DetourHomeDaemonClient.baseURL
    }

    var chainPoints: [DetourWalletChartPoint] {
        guard let dashboard else { return [] }
        let grouped = Dictionary(grouping: dashboard.assets, by: { displayChain($0.chain) })
        return grouped.map { chain, assets in
            DetourWalletChartPoint(label: chain, value: Double(assets.count), tint: tint(for: chain))
        }
        .sorted { $0.label < $1.label }
    }

    var capabilityPoints: [DetourWalletChartPoint] {
        guard let dashboard else { return [] }
        let ready = dashboard.capabilities.filter { $0.enabled && $0.configured }.count
        let needsSetup = dashboard.capabilities.filter { $0.enabled && !$0.configured }.count
        let disabled = dashboard.capabilities.filter { !$0.enabled }.count
        return [
            DetourWalletChartPoint(label: "Ready", value: Double(ready), tint: .green),
            DetourWalletChartPoint(label: "Needs setup", value: Double(needsSetup), tint: .orange),
            DetourWalletChartPoint(label: "Off", value: Double(disabled), tint: .secondary),
        ].filter { $0.value > 0 }
    }

    var highlightedCapabilities: [WalletTradingCapabilitySummary] {
        guard let dashboard else { return [] }
        let priority = [
            "solana.read",
            "evm.read",
            "hyperliquid.market_data",
            "hyperliquid.trading",
            "jupiter.swaps",
            "uniswap.swaps",
            "pancakeswap.planner",
        ]
        return dashboard.capabilities.sorted { left, right in
            (priority.firstIndex(of: left.id) ?? Int.max, left.name)
                < (priority.firstIndex(of: right.id) ?? Int.max, right.name)
        }
        .prefix(8)
        .map { $0 }
    }

    func refresh() {
        guard state != .loading else { return }
        state = .loading
        Task { await load() }
    }

    func markOffline(_ message: String) {
        dashboard = nil
        state = .failed(DetourSetupInsightRedaction.display(message))
    }

    private func load() async {
        do {
            let response = try await DetourHomeDaemonClient.makeEnsuringDaemon().walletDashboard()
            dashboard = response
            state = .loaded(response.generatedAt)
        } catch {
            dashboard = nil
            state = .failed(DetourHomeDaemonClient.display(error))
        }
    }

    private func displayChain(_ chain: String) -> String {
        switch chain.lowercased() {
        case "solana":
            "Solana"
        case "ethereum":
            "Ethereum"
        case "base":
            "Base"
        case "bnb":
            "BNB Chain"
        default:
            chain
        }
    }

    private func tint(for chain: String) -> DetourWalletChartTint {
        switch chain.lowercased() {
        case "solana":
            .purple
        case "bnb chain", "bnb":
            .yellow
        case "base":
            .blue
        case "ethereum":
            .indigo
        default:
            .green
        }
    }
}

struct DetourWalletChartPoint: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var value: Double
    var tint: DetourWalletChartTint
}

enum DetourWalletChartTint: Equatable {
    case blue
    case green
    case indigo
    case orange
    case purple
    case secondary
    case yellow
}
