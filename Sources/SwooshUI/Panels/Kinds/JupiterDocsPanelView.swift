// SwooshUI/Panels/Kinds/JupiterDocsPanelView.swift — 0.9R Jupiter docs coverage panel
import SwiftUI
import SwooshGenerativeUI

struct JupiterDocsPanelView: View {
    private let areas = JupiterDocsArea.all

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            summaryRows
            Divider().opacity(0.18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(areas) { area in
                        JupiterDocsAreaRow(area: area)
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
            KVRow(key: "source", value: "developers.jup.ag/docs/llms.txt", accent: .green)
            KVRow(key: "coverage", value: "\(areas.count) product areas", accent: .cyan)
            HStack(spacing: 8) {
                Link(destination: JupiterDocsURL.llms) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .help("Open llms.txt")
                .buttonStyle(.plain)

                Link(destination: JupiterDocsURL.full) {
                    Image(systemName: "doc.richtext")
                }
                .help("Open llms-full.txt")
                .buttonStyle(.plain)

                Link(destination: JupiterDocsURL.portal) {
                    Image(systemName: "key")
                }
                .help("Open Jupiter Developer Platform")
                .buttonStyle(.plain)

                Link(destination: JupiterDocsURL.status) {
                    Image(systemName: "waveform.path.ecg")
                }
                .help("Open Jupiter API status")
                .buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SwooshNeonTokens.Accent.green)
        }
    }
}

private struct JupiterDocsAreaRow: View {
    let area: JupiterDocsArea

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

private struct JupiterDocsArea: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let surface: String
    let status: JupiterDocsStatus
    let systemImage: String
    let url: URL

    static let all: [JupiterDocsArea] = [
        .init(
            id: "get-started",
            title: "Get Started",
            summary: "Environment setup, Solana basics, API quickstarts, and guides.",
            surface: "Docs, environment setup, development basics, guides",
            status: .docs,
            systemImage: "play.circle",
            url: JupiterDocsURL.getStarted
        ),
        .init(
            id: "portal",
            title: "Developer Platform",
            summary: "API keys, rate limits, plans, response codes, latency, and migration notes.",
            surface: "x-api-key, 0.5 RPS keyless, rate-limit and status UX",
            status: .docs,
            systemImage: "key",
            url: JupiterDocsURL.portalSetup
        ),
        .init(
            id: "ai",
            title: "AI Resources",
            summary: "Agent skills, CLI, docs MCP, llms.txt, and complete Markdown docs.",
            surface: "Bundled skills, docs links, jup CLI and MCP references",
            status: .skill,
            systemImage: "sparkles",
            url: JupiterDocsURL.ai
        ),
        .init(
            id: "swap",
            title: "Swap API V2",
            summary: "Meta-Aggregator order/execute and Router build/submit paths.",
            surface: "jupiter.order, execute, build, balances, routers, shield",
            status: .live,
            systemImage: "arrow.left.arrow.right",
            url: JupiterDocsURL.swap
        ),
        .init(
            id: "tokens",
            title: "Tokens + VRFD",
            summary: "Token search, tags, recent mints, content, verification, and organic score.",
            surface: "token tools live; VRFD surfaced by bundled skill",
            status: .live,
            systemImage: "checkmark.seal",
            url: JupiterDocsURL.tokens
        ),
        .init(
            id: "price",
            title: "Price API",
            summary: "Real-time USD pricing for up to 50 SPL token mints per request.",
            surface: "jupiter.price with manipulated-price filtering context",
            status: .live,
            systemImage: "chart.line.uptrend.xyaxis",
            url: JupiterDocsURL.price
        ),
        .init(
            id: "jupusd",
            title: "JupUSD",
            summary: "Mint/redeem flows, JUICED collateral, benefactor requirements, and risk notes.",
            surface: "Docs surfaced; no native execution tool yet",
            status: .docs,
            systemImage: "dollarsign.circle",
            url: JupiterDocsURL.jupUSD
        ),
        .init(
            id: "lend",
            title: "Lend",
            summary: "Earn, Borrow, flashloans, liquidity analytics, advanced vault recipes, and program IDs.",
            surface: "Bundled jupiter-lend skill; no native lend signer tool yet",
            status: .skill,
            systemImage: "banknote",
            url: JupiterDocsURL.lend
        ),
        .init(
            id: "trigger",
            title: "Trigger V2",
            summary: "Vault-backed limit orders, auth challenge, order management, history, and best practices.",
            surface: "Docs v2 surfaced; legacy trigger tool needs migration",
            status: .migration,
            systemImage: "scope",
            url: JupiterDocsURL.trigger
        ),
        .init(
            id: "recurring",
            title: "Recurring",
            summary: "Time-based DCA create, execute, cancel, list, and minimum-order guidance.",
            surface: "Time DCA live; price-order deposit/withdraw marked deprecated",
            status: .live,
            systemImage: "clock.arrow.circlepath",
            url: JupiterDocsURL.recurring
        ),
        .init(
            id: "prediction",
            title: "Prediction",
            summary: "Events, markets, orderbooks, positions, payouts, profiles, and leaderboards.",
            surface: "Docs surfaced; no native prediction signer tool yet",
            status: .docs,
            systemImage: "chart.xyaxis.line",
            url: JupiterDocsURL.prediction
        ),
        .init(
            id: "portfolio",
            title: "Portfolio",
            summary: "Wallet positions, staked JUP, Jupiter-specific positions, and platform metadata.",
            surface: "Wallet UX placeholder; API docs surfaced",
            status: .docs,
            systemImage: "briefcase",
            url: JupiterDocsURL.portfolio
        ),
        .init(
            id: "send",
            title: "Send",
            summary: "Invite-code token sends, pending invites, history, and clawback flows.",
            surface: "Docs surfaced; no native send signer tool yet",
            status: .docs,
            systemImage: "paperplane",
            url: JupiterDocsURL.send
        ),
        .init(
            id: "studio",
            title: "Studio",
            summary: "Token creation, Dynamic Bonding Curve launch transactions, and creator fee claims.",
            surface: "Docs surfaced; no native token-launch signer tool yet",
            status: .docs,
            systemImage: "cube.transparent",
            url: JupiterDocsURL.studio
        ),
        .init(
            id: "lock",
            title: "Lock",
            summary: "Audited token locking and vesting program references.",
            surface: "Docs surfaced for token distribution workflows",
            status: .docs,
            systemImage: "lock",
            url: JupiterDocsURL.lock
        ),
        .init(
            id: "perps",
            title: "Perps",
            summary: "Perpetuals account references for positions, requests, pools, and custody.",
            surface: "Docs surfaced; no native perps execution tool yet",
            status: .docs,
            systemImage: "arrow.up.right.circle",
            url: JupiterDocsURL.perps
        ),
        .init(
            id: "tool-kits",
            title: "Tool Kits",
            summary: "Jupiter Plugin, Wallet Kit, Mobile Adapter, and Referral Program.",
            surface: "UX integration docs surfaced; native app chooses Swoosh wallet",
            status: .docs,
            systemImage: "puzzlepiece",
            url: JupiterDocsURL.toolKits
        ),
        .init(
            id: "resources",
            title: "Resources + Legal",
            summary: "Changelog, support, brand kit, stats, audits, references, license, terms, and privacy.",
            surface: "Support, status, audits, changelog, and legal links",
            status: .docs,
            systemImage: "doc.append",
            url: JupiterDocsURL.resources
        ),
    ]
}

private enum JupiterDocsStatus: String, Equatable {
    case live = "LIVE"
    case skill = "SKILL"
    case docs = "DOCS"
    case migration = "MIGRATE"

    var accent: NeonAccent {
        switch self {
        case .live: return .green
        case .skill: return .cyan
        case .docs: return .gold
        case .migration: return .gold
        }
    }
}

private enum JupiterDocsURL {
    static let llms = required("https://developers.jup.ag/docs/llms.txt")
    static let full = required("https://developers.jup.ag/docs/llms-full.txt")
    static let portal = required("https://developers.jup.ag/portal")
    static let status = required("https://status.jup.ag/")
    static let getStarted = required("https://developers.jup.ag/docs/get-started/index.md")
    static let portalSetup = required("https://developers.jup.ag/docs/portal/setup.md")
    static let ai = required("https://developers.jup.ag/docs/ai/index.md")
    static let swap = required("https://developers.jup.ag/docs/swap/index.md")
    static let tokens = required("https://developers.jup.ag/docs/tokens/index.md")
    static let price = required("https://developers.jup.ag/docs/price/index.md")
    static let jupUSD = required("https://developers.jup.ag/docs/jupusd/index.md")
    static let lend = required("https://developers.jup.ag/docs/lend/index.md")
    static let trigger = required("https://developers.jup.ag/docs/trigger/index.md")
    static let recurring = required("https://developers.jup.ag/docs/recurring/index.md")
    static let prediction = required("https://developers.jup.ag/docs/prediction/index.md")
    static let portfolio = required("https://developers.jup.ag/docs/portfolio/index.md")
    static let send = required("https://developers.jup.ag/docs/send/index.md")
    static let studio = required("https://developers.jup.ag/docs/studio/index.md")
    static let lock = required("https://developers.jup.ag/docs/lock/index.md")
    static let perps = required("https://developers.jup.ag/docs/perps/index.md")
    static let toolKits = required("https://developers.jup.ag/docs/tool-kits/index.md")
    static let resources = required("https://developers.jup.ag/docs/resources/support.md")

    private static func required(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid Jupiter docs URL: \(value)")
        }
        return url
    }
}
