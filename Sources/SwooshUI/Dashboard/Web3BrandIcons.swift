// SwooshUI/Dashboard/Web3BrandIcons.swift — Inline SVG brand icons for Web3 platforms — 0.9V
//
// Provides Shape-based brand icons for launchpad platforms and chains.
// Uses SwiftUI Path drawing so no external asset files are needed.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Launchpad brand icons
// ═══════════════════════════════════════════════════════════════════

public enum Web3BrandIcon {

    // MARK: - PumpPortal (lightning bolt in circle)
    public struct PumpPortalIcon: View {
        let size: CGFloat
        let color: Color

        public init(size: CGFloat = 24, color: Color = VoltPaper.primary) {
            self.size = size
            self.color = color
        }

        public var body: some View {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: size, height: size)
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Bags (bag with checkmark)
    public struct BagsIcon: View {
        let size: CGFloat
        let color: Color

        public init(size: CGFloat = 24, color: Color = VoltPaper.primary) {
            self.size = size
            self.color = color
        }

        public var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: size, height: size)
                Image(systemName: "bag.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Flap (bird wings)
    public struct FlapIcon: View {
        let size: CGFloat
        let color: Color

        public init(size: CGFloat = 24, color: Color = VoltPaper.Chart.c4) {
            self.size = size
            self.color = color
        }

        public var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: size, height: size)
                Image(systemName: "bird.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Four.meme (4 in diamond)
    public struct FourMemeIcon: View {
        let size: CGFloat
        let color: Color

        public init(size: CGFloat = 24, color: Color = VoltPaper.Chart.c4) {
            self.size = size
            self.color = color
        }

        public var body: some View {
            ZStack {
                // Diamond shape
                Rectangle()
                    .fill(color.opacity(0.15))
                    .frame(width: size * 0.8, height: size * 0.8)
                    .rotationEffect(.degrees(45))
                    .frame(width: size, height: size)
                Text("4")
                    .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Chain icons

    public struct SolanaIcon: View {
        let size: CGFloat

        public init(size: CGFloat = 20) { self.size = size }

        public var body: some View {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.2, blue: 1.0),
                                Color(red: 0.0, green: 0.9, blue: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                // Three horizontal bars (Solana logo shape)
                VStack(spacing: size * 0.06) {
                    SolanaBar(width: size * 0.55, height: size * 0.1)
                    SolanaBar(width: size * 0.55, height: size * 0.1)
                    SolanaBar(width: size * 0.55, height: size * 0.1)
                }
            }
        }
    }

    public struct BNBIcon: View {
        let size: CGFloat

        public init(size: CGFloat = 20) { self.size = size }

        public var body: some View {
            ZStack {
                Circle()
                    .fill(Color(red: 0.96, green: 0.73, blue: 0.08))
                    .frame(width: size, height: size)
                // BNB diamond shape
                Rectangle()
                    .fill(.white)
                    .frame(width: size * 0.35, height: size * 0.35)
                    .rotationEffect(.degrees(45))
            }
        }
    }

    public struct EthereumIcon: View {
        let size: CGFloat

        public init(size: CGFloat = 20) { self.size = size }

        public var body: some View {
            ZStack {
                Circle()
                    .fill(Color(red: 0.4, green: 0.4, blue: 0.9))
                    .frame(width: size, height: size)
                // ETH diamond
                Image(systemName: "diamond.fill")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Resolver

    @MainActor @ViewBuilder
    public static func icon(for platformID: String, size: CGFloat = 32) -> some View {
        switch platformID {
        case "pumpportal":
            PumpPortalIcon(size: size, color: VoltPaper.primary)
        case "bags":
            BagsIcon(size: size, color: Color(red: 0.6, green: 0.2, blue: 1.0))
        case "flap":
            FlapIcon(size: size, color: VoltPaper.Chart.c4)
        case "four-meme":
            FourMemeIcon(size: size, color: VoltPaper.Chart.c4)
        default:
            ZStack {
                Circle()
                    .fill(VoltPaper.mutedFg.opacity(0.15))
                    .frame(width: size, height: size)
                Image(systemName: "rocket.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(VoltPaper.mutedFg)
            }
        }
    }

    @MainActor @ViewBuilder
    public static func chainIcon(for chain: String, size: CGFloat = 20) -> some View {
        switch chain.lowercased() {
        case "solana":
            SolanaIcon(size: size)
        case "bnb chain", "bsc", "bnb":
            BNBIcon(size: size)
        case "ethereum", "eth":
            EthereumIcon(size: size)
        default:
            Circle()
                .fill(VoltPaper.mutedFg.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(chain.prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(VoltPaper.foreground)
                )
        }
    }
}

// Solana bar helper
private struct SolanaBar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height * 0.5)
            .fill(.white)
            .frame(width: width, height: height)
    }
}

#endif
