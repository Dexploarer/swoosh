// SwooshUI/Dashboard/WalletPane+Connected.swift — Wallet dashboard leaf renderers — 0.9Y
//
// Pure param→view builders extracted from WalletPane to keep that file under
// the LOC ceiling. No @State, no networking — connectedDashboard/disconnectedState
// (in WalletPane.swift) compose these.

#if os(macOS)
import SwiftUI
import SwooshGenerativeUI
import SwooshClient

extension WalletPane {

    // ── Analytics card ───────────────────────────────────────────

    func analyticCard(_ label: String, value: String?, prefix: String = "", suffix: String = "") -> some View {
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

    func analyticCard(_ label: String, value: String) -> some View {
        analyticCard(label, value: Optional(value))
    }

    // ── Asset table ──────────────────────────────────────────────

    func assetTable(_ assets: [WalletAssetSummary]) -> some View {
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

    func insightsSection(_ insights: [WalletInsightSummary]) -> some View {
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
    func pnlText(_ value: String?, prefix: String = "", suffix: String = "") -> some View {
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

    func severityColor(_ severity: WalletInsightSeverity) -> Color {
        switch severity {
        case .info: return SwooshNeonTokens.Accent.cyan
        case .warning: return VoltPaper.Chart.c4
        case .critical: return VoltPaper.destructive
        }
    }

    func chainColorForAsset(_ chain: String) -> Color {
        switch chain.lowercased() {
        case "solana", "sol": return VoltPaper.Chart.c1
        case "ethereum", "eth": return VoltPaper.Chart.c3
        case "bnb", "bsc", "bnb chain": return VoltPaper.Chart.c4
        default: return VoltPaper.mutedFg
        }
    }
}

#endif
