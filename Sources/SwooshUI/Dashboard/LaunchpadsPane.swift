// SwooshUI/Dashboard/LaunchpadsPane.swift — Live token launchpad — 0.9X
//
// Shows each platform as a compact card with LAUNCH button.
// Below: live token feed from each platform. No docs/notes filler.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct LaunchpadsPane: View {
    @State private var platforms: [LaunchpadPlatformSummary] = []
    @State private var selectedPlatform: String?
    @State private var isLoading = true
    @State private var isConnected = false
    @State private var showLaunchSheet = false
    @State private var launchPlatformID = ""

    public init() {}

    private var staticPlatforms: [LaunchpadPlatformSummary] {
        SwooshLaunchpadCatalog.details.map(\.platform)
    }

    private var displayPlatforms: [LaunchpadPlatformSummary] {
        platforms.isEmpty ? staticPlatforms : platforms
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                platformGrid
                liveTokenFeed
            }
            .padding(24)
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadPlatforms() }
        .sheet(isPresented: $showLaunchSheet) {
            LaunchTokenSheet(
                platformID: launchPlatformID,
                platformName: displayPlatforms.first { $0.id == launchPlatformID }?.name ?? launchPlatformID,
                onClose: { showLaunchSheet = false }
            )
        }
    }

    // ── Header ────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Launchpads")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("\(displayPlatforms.count) platforms · Solana & BNB Chain")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Spacer()
            connectionBadge
            Button { Task { await loadPlatforms() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .buttonStyle(.plain)
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isConnected ? VoltPaper.accent : VoltPaper.destructive)
                .frame(width: 7, height: 7)
                .shadow(color: isConnected ? VoltPaper.accent.opacity(0.5) : .clear, radius: 3)
            Text(isConnected ? "Connected" : "Offline")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isConnected ? VoltPaper.accent : SwooshNeonTokens.Canvas.text3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(VoltPaper.foreground.opacity(0.04))
        .clipShape(Capsule())
    }

    // ── Platform grid (2x2) ──────────────────────────────────────

    private var platformGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            ForEach(displayPlatforms) { platform in
                platformCard(platform)
            }
        }
    }

    private func platformCard(_ platform: LaunchpadPlatformSummary) -> some View {
        let isSelected = selectedPlatform == platform.id
        let chainCol = chainColor(platform.chain)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Web3BrandIcon.icon(for: platform.id, size: 36)
                    .shadow(color: chainCol.opacity(0.3), radius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    HStack(spacing: 5) {
                        Web3BrandIcon.chainIcon(for: platform.chain, size: 11)
                        Text(platform.chain)
                            .font(.system(size: 10))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        riskBadge(platform.risk)
                    }
                }
                Spacer()

                Button {
                    launchPlatformID = platform.id
                    showLaunchSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("Launch")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(VoltPaper.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(chainCol.gradient)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Capabilities as compact pills
            HStack(spacing: 4) {
                ForEach(platform.capabilities.prefix(4), id: \.self) { cap in
                    Text(cap.replacingOccurrences(of: "-", with: " "))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(chainCol)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(chainCol.opacity(0.08))
                        .clipShape(Capsule())
                }
                if platform.capabilities.count > 4 {
                    Text("+\(platform.capabilities.count - 4)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? chainCol.opacity(0.06) : VoltPaper.foreground.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? chainCol.opacity(0.4) : SwooshNeonTokens.Line.rule,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .onTapGesture { selectedPlatform = platform.id }
    }

    // ── Live token feed ──────────────────────────────────────────

    @ViewBuilder
    private var liveTokenFeed: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                Text("Live Launches")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Spacer()
                if let sel = selectedPlatform, let name = displayPlatforms.first(where: { $0.id == sel })?.name {
                    Text("Filtering: \(name)")
                        .font(.system(size: 10))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    Button { selectedPlatform = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isConnected {
                // Not connected state
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3.opacity(0.4))
                    Text("Connect to see live token launches")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    Text("Start the daemon to stream real-time launches from PumpPortal, Bags, Flap, and Four.meme")
                        .font(.system(size: 11))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await loadPlatforms() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Connection")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SwooshNeonTokens.Accent.cyan.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Connected but no live data yet
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for new token launches…")
                        .font(.system(size: 12))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VoltPaper.foreground.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
        )
    }

    // ── Helpers ───────────────────────────────────────────────────

    @ViewBuilder
    private func riskBadge(_ risk: String) -> some View {
        let color = riskColor(risk)
        Text(risk.uppercased())
            .font(.system(size: 7, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func chainColor(_ chain: String) -> Color {
        switch chain.lowercased() {
        case "solana": return VoltPaper.Chart.c1
        case "bnb chain", "bsc", "bnb": return VoltPaper.Chart.c4
        case "ethereum": return VoltPaper.Chart.c3
        default: return VoltPaper.mutedFg
        }
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk.lowercased() {
        case "high", "critical": return VoltPaper.destructive
        case "medium": return VoltPaper.Chart.c4
        case "low": return VoltPaper.accent
        default: return VoltPaper.mutedFg
        }
    }

    // ── Network ──────────────────────────────────────────────────

    private func loadPlatforms() async {
        isLoading = true
        defer { isLoading = false }
        guard let client = SwooshDaemonClient.client() else {
            isConnected = false
            return
        }
        do {
            let response = try await client.launchpads()
            platforms = response.platforms
            isConnected = true
        } catch {
            isConnected = false
        }
    }
}

// ── Flow layout (shared) ─────────────────────────────────────────

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

#endif
