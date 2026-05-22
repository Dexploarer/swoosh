// SwooshUI/Panels/Kinds/DeFiDocsPanelView.swift - 0.9R DeFi docs and skill coverage
import SwiftUI
import SwooshGenerativeUI

struct DeFiDocsPanelView: View {
    private let areas = DeFiDocsArea.all

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            summaryRows
            Divider().opacity(0.18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(areas) { area in
                        DeFiDocsAreaRow(area: area)
                        if area.id != areas.last?.id {
                            Divider().opacity(0.12)
                        }
                    }
                }
            }
            .frame(minHeight: 260)
        }
    }

    private var summaryRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            KVRow(key: "solana", value: "Jupiter + Pay API wallet", accent: .green)
            KVRow(key: "evm", value: "Uniswap + PancakeSwap AI", accent: .cyan)
            HStack(spacing: 8) {
                Link(destination: DeFiDocsURL.payDocs) {
                    Image(systemName: "creditcard.and.123")
                }
                .help("Open Pay docs")
                .buttonStyle(.plain)

                Link(destination: DeFiDocsURL.pancakeDocs) {
                    Image(systemName: "square.stack.3d.up")
                }
                .help("Open PancakeSwap AI docs")
                .buttonStyle(.plain)

                Link(destination: DeFiDocsURL.pancakeAgentIndex) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("Open PancakeSwap agent index")
                .buttonStyle(.plain)

                Link(destination: DeFiDocsURL.pancakeApp) {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open PancakeSwap app")
                .buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SwooshNeonTokens.Accent.green)
        }
    }
}

private struct DeFiDocsAreaRow: View {
    let area: DeFiDocsArea

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: area.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(area.status.accent.color)
                .frame(width: 18)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(area.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        .lineLimit(1)
                    MonoChip(text: area.chain, accent: area.chainAccent)
                    MonoChip(text: area.status.rawValue, accent: area.status.accent)
                }

                Text(area.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    .lineLimit(2)

                Text(area.surface)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Link(destination: area.url) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .help("Open \(area.title) docs")
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 9)
    }
}

private struct DeFiDocsArea: Identifiable, Equatable {
    let id: String
    let title: String
    let chain: String
    let summary: String
    let surface: String
    let status: DeFiDocsStatus
    let systemImage: String
    let url: URL

    var chainAccent: NeonAccent {
        switch chain {
        case "SOL": return .green
        case "EVM": return .cyan
        default: return .gold
        }
    }

    static let all: [DeFiDocsArea] = [
        .init(
            id: "pay",
            title: "Pay API Wallet",
            chain: "SOL",
            summary: "Wallet-approved paid API calls, HTTP 402/x402/MPP providers, sandbox tests, and catalog discovery.",
            surface: "Bundled pay-sh-api-wallet skill; runtime uses Pay MCP when attached",
            status: .mcp,
            systemImage: "creditcard.and.123",
            url: DeFiDocsURL.payDocs
        ),
        .init(
            id: "jupiter",
            title: "Jupiter",
            chain: "SOL",
            summary: "Swap, tokens, price, lend, trigger, recurring, portfolio, send, studio, lock, and perps docs.",
            surface: "Native Solana/Jupiter tools plus bundled jup-ag agent skills",
            status: .live,
            systemImage: "sparkles",
            url: DeFiDocsURL.jupiterDocs
        ),
        .init(
            id: "pancakeswap-swap",
            title: "PancakeSwap Swap",
            chain: "EVM",
            summary: "Swap planning, token discovery, price checks, supported-chain selection, and wallet-confirmed deep links.",
            surface: "Bundled swap-planner and swap-integration skills; no silent execution",
            status: .skill,
            systemImage: "arrow.left.arrow.right",
            url: DeFiDocsURL.pancakeSwapSkill
        ),
        .init(
            id: "pancakeswap-liquidity",
            title: "PancakeSwap Liquidity",
            chain: "EVM",
            summary: "V2, V3, StableSwap, Infinity positions, fee tiers, APR/APY analysis, and position deep links.",
            surface: "Bundled liquidity-planner, collect-fees, farming, and harvest skills",
            status: .skill,
            systemImage: "drop.triangle",
            url: DeFiDocsURL.pancakeLiquiditySkill
        ),
        .init(
            id: "pancakeswap-hub",
            title: "PancakeSwap Hub",
            chain: "EVM",
            summary: "PCS Hub routing and integration guidance for partner wallets and app distribution channels.",
            surface: "Bundled hub-swap-planner and hub-api-integration skills",
            status: .skill,
            systemImage: "point.3.connected.trianglepath.dotted",
            url: DeFiDocsURL.pancakePlugins
        ),
        .init(
            id: "uniswap",
            title: "Uniswap",
            chain: "EVM",
            summary: "Existing EVM quote, swap-builder, and pool inspection path.",
            surface: "Native uniswap toolset remains the direct EVM transaction builder",
            status: .live,
            systemImage: "diamond",
            url: DeFiDocsURL.uniswapDocs
        ),
    ]
}

private enum DeFiDocsStatus: String, Equatable {
    case live = "LIVE"
    case skill = "SKILL"
    case mcp = "MCP"

    var accent: NeonAccent {
        switch self {
        case .live: return .green
        case .skill: return .cyan
        case .mcp: return .gold
        }
    }
}

private enum DeFiDocsURL {
    static let payDocs = required("https://pay.sh/docs")
    static let pancakeDocs = required("https://pancakeswap.ai/getting-started/")
    static let pancakeAgentIndex = required("https://raw.githubusercontent.com/pancakeswap/pancakeswap-ai/main/AGENTS.md")
    static let pancakeApp = required("https://pancakeswap.finance/")
    static let pancakeSwapSkill = required("https://pancakeswap.ai/skills/swap-planner.html")
    static let pancakeLiquiditySkill = required("https://pancakeswap.ai/skills/liquidity-planner.html")
    static let pancakePlugins = required("https://pancakeswap.ai/plugins/")
    static let jupiterDocs = required("https://developers.jup.ag/docs/llms.txt")
    static let uniswapDocs = required("https://developers.uniswap.org/docs/uniswap-ai/skills")

    private static func required(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid DeFi docs URL: \(value)")
        }
        return url
    }
}
