// SwooshUI/Panels/Kinds/LaunchpadDocsPanelView.swift - 0.9R Launchpad docs coverage
import SwiftUI
import SwooshGenerativeUI

struct LaunchpadDocsPanelView: View {
    private let platforms = LaunchpadDocsPlatform.all

    var body: some View {
        VStack(alignment: .leading, spacing: SwooshNeonTokens.Spacing.micro) {
            summaryRows
            Divider().opacity(0.18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(platforms) { platform in
                        LaunchpadDocsPlatformRow(platform: platform)
                        if platform.id != platforms.last?.id {
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
            KVRow(key: "solana", value: "PumpPortal + Bags", accent: .green)
            KVRow(key: "evm", value: "Flap + Four.meme on BNB Chain", accent: .cyan)
            KVRow(key: "agent", value: "4 bundled skills + launchpad catalog tools", accent: .gold)
            HStack(spacing: 8) {
                Link(destination: LaunchpadDocsURL.pumpportal) {
                    Image(systemName: "flame")
                }
                .help("Open PumpPortal docs")
                .buttonStyle(.plain)

                Link(destination: LaunchpadDocsURL.bags) {
                    Image(systemName: "bag")
                }
                .help("Open Bags docs")
                .buttonStyle(.plain)

                Link(destination: LaunchpadDocsURL.flap) {
                    Image(systemName: "bolt")
                }
                .help("Open Flap docs")
                .buttonStyle(.plain)

                Link(destination: LaunchpadDocsURL.fourMeme) {
                    Image(systemName: "4.circle")
                }
                .help("Open Four.meme docs")
                .buttonStyle(.plain)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SwooshNeonTokens.Accent.green)
        }
    }
}

private struct LaunchpadDocsPlatformRow: View {
    let platform: LaunchpadDocsPlatform

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: platform.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(platform.status.accent.color)
                .frame(width: 18)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(platform.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                        .lineLimit(1)
                    MonoChip(text: platform.chain, accent: platform.chainAccent)
                    MonoChip(text: platform.status.rawValue, accent: platform.status.accent)
                }

                Text(platform.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    .lineLimit(2)

                Text(platform.surface)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Link(destination: platform.url) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .help("Open \(platform.title) docs")
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 9)
    }
}

private struct LaunchpadDocsPlatform: Identifiable, Equatable {
    let id: String
    let title: String
    let chain: String
    let summary: String
    let surface: String
    let status: LaunchpadDocsStatus
    let systemImage: String
    let url: URL

    var chainAccent: NeonAccent {
        switch chain {
        case "SOL": return .green
        case "BNB": return .cyan
        default: return .gold
        }
    }

    static let all: [LaunchpadDocsPlatform] = [
        .init(
            id: "pumpportal",
            title: "PumpPortal",
            chain: "SOL",
            summary: "Token creation, Pump.fun and PumpSwap trading, Lightning execution, local transaction builds, and live data streams.",
            surface: "pumpportal-launchpad skill; launchpad.list_platforms and get_platform",
            status: .skill,
            systemImage: "flame",
            url: LaunchpadDocsURL.pumpportalTrading
        ),
        .init(
            id: "bags",
            title: "Bags",
            chain: "SOL",
            summary: "Agent authentication, launch intents, launch-token guides, and create-token-launch-transaction API.",
            surface: "bags-launchpad skill; draft-first Solana launch workflow",
            status: .skill,
            systemImage: "bag",
            url: LaunchpadDocsURL.bagsLaunch
        ),
        .init(
            id: "flap",
            title: "Flap",
            chain: "BNB",
            summary: "Wallet, terminal, bot, token launcher, VaultPortal, deployed contract, and Blink-style integration docs.",
            surface: "flap-launchpad skill; EVM wallet approval path",
            status: .skill,
            systemImage: "bolt",
            url: LaunchpadDocsURL.flap
        ),
        .init(
            id: "four-meme",
            title: "Four.meme",
            chain: "BNB",
            summary: "BNB meme launches, TokenManager helpers, tax-token settings, bonding curve, and PancakeSwap graduation.",
            surface: "four-meme-launchpad skill; EVM contract planning path",
            status: .skill,
            systemImage: "4.circle",
            url: LaunchpadDocsURL.fourMemeProtocol
        ),
    ]
}

private enum LaunchpadDocsStatus: String, Equatable {
    case skill = "SKILL"

    var accent: NeonAccent {
        switch self {
        case .skill: return .gold
        }
    }
}

private enum LaunchpadDocsURL {
    static let pumpportal = required("https://pumpportal.fun/")
    static let pumpportalTrading = required("https://pumpportal.fun/trading-api/")
    static let bags = required("https://docs.bags.fm/llms.txt")
    static let bagsLaunch = required("https://docs.bags.fm/how-to-guides/launch-token")
    static let flap = required("https://docs.flap.sh/flap")
    static let fourMeme = required("https://four-meme.gitbook.io/four.meme/guide/how-it-works")
    static let fourMemeProtocol = required("https://four-meme.gitbook.io/four.meme/brand/protocol-integration")

    private static func required(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid launchpad docs URL: \(value)")
        }
        return url
    }
}
