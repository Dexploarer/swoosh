// SwooshUI/MenuBar/WalletTrayChart.swift — Wallet tray portfolio chart — 0.2A
//
// Compact Swift Charts view for the menu-bar Wallet panel. Renders the REAL
// holdings from WalletDashboardResponse.assets (balances are fetched on-chain
// by the daemon via SolanaRPC / EVMRPC). When the daemon supplies USD values
// it draws an allocation donut (SectorMark); otherwise it draws an honest
// per-asset balance bar chart (BarMark) labeled with the native amount.
//
// A 2D⇄3D toggle switches the flat chart for a macOS-26 `Chart3D` holdings
// scatter (asset × value × chain). Volt Paper palette only — no neon.

#if os(macOS)

import SwiftUI
import Charts
import SwooshClient
import SwooshGenerativeUI

struct WalletTrayChart: View {
    let assets: [WalletAssetSummary]

    enum Mode: String, CaseIterable { case flat = "2D", spatial = "3D" }
    @State private var mode: Mode = .flat

    struct Entry: Identifiable {
        let id: String
        let symbol: String
        let chain: String
        let chainIndex: Double
        let magnitude: Double   // USD value when valued, else native amount
        let display: String
        let color: Color
    }

    /// Parse a leading decimal out of a display string ("1.42 SOL" → 1.42,
    /// "$12,300.50" → 12300.5). Returns nil when there's no number.
    static func number(_ s: String?) -> Double? {
        guard let s else { return nil }
        let cleaned = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        var digits = ""
        for ch in cleaned {
            if ch.isNumber || ch == "." || (digits.isEmpty && ch == "-") { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Double(digits)
    }

    private var valued: Bool { assets.contains { Self.number($0.valueUSD) != nil } }

    private var entries: [Entry] {
        let palette = VoltPaper.Chart.all
        var chainOrder: [String: Double] = [:]
        return assets.enumerated().compactMap { idx, a in
            let mag = valued ? (Self.number(a.valueUSD) ?? 0) : (Self.number(a.quantity) ?? 0)
            guard mag > 0 else { return nil }
            let cIdx = chainOrder[a.chain] ?? Double(chainOrder.count)
            chainOrder[a.chain] = cIdx
            return Entry(
                id: a.id, symbol: a.symbol, chain: a.chain, chainIndex: cIdx,
                magnitude: mag,
                display: valued ? "$\(a.valueUSD ?? "0")" : a.quantity,
                color: palette[idx % palette.count]
            )
        }
    }

    var body: some View {
        let data = entries
        VStack(alignment: .leading, spacing: 8) {
            header
            if data.isEmpty {
                Text("No on-chain balance yet.")
                    .font(.system(size: 11)).foregroundStyle(VoltPaper.mutedFg).padding(.vertical, 6)
            } else if mode == .spatial {
                spatial(data)
            } else if valued {
                donut(data)
            } else {
                bars(data)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VoltPaper.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(VoltPaper.border, lineWidth: 0.5))
    }

    private var header: some View {
        HStack {
            TraySectionLabel(text: valued ? "Allocation" : "Balances")
            Spacer(minLength: 8)
            modeToggle
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(mode == m ? VoltPaper.accentFg : VoltPaper.mutedFg)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(mode == m ? VoltPaper.accent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(VoltPaper.foreground.opacity(0.06)))
    }

    // 2D allocation donut (SectorMark) — when USD values are present.
    private func donut(_ data: [Entry]) -> some View {
        HStack(spacing: 14) {
            Chart(data) { e in
                SectorMark(angle: .value("Value", e.magnitude), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3).foregroundStyle(e.color)
            }
            .chartLegend(.hidden).frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 5) { ForEach(data.prefix(5)) { legendRow($0) } }
        }
    }

    // 2D honest per-asset balance bars (native amounts, labeled).
    private func bars(_ data: [Entry]) -> some View {
        Chart(data) { e in
            BarMark(x: .value("Amount", e.magnitude), y: .value("Asset", e.symbol))
                .cornerRadius(4).foregroundStyle(e.color)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(e.display).font(.system(size: 9, weight: .medium)).foregroundStyle(VoltPaper.mutedFg)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(preset: .aligned, position: .leading) { _ in AxisValueLabel().font(.system(size: 10, weight: .semibold)) } }
        .frame(height: CGFloat(min(data.count, 5)) * 26 + 8)
    }

    // macOS 26 Chart3D — holdings scatter: asset (x) × value (y) × chain (z).
    private func spatial(_ data: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart3D(data) { e in
                PointMark(
                    x: .value("Asset", e.symbol),
                    y: .value("Value", e.magnitude),
                    z: .value("Chain", e.chain)
                )
                .foregroundStyle(e.color)
            }
            .chart3DCameraProjection(.perspective)
            .frame(height: 150)
            HStack(spacing: 10) { ForEach(data.prefix(4)) { legendChip($0) } }
        }
    }

    private func legendRow(_ e: Entry) -> some View {
        HStack(spacing: 6) {
            Circle().fill(e.color).frame(width: 7, height: 7)
            Text(e.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(VoltPaper.foreground)
            Spacer(minLength: 6)
            Text(e.display).font(.system(size: 10, design: .monospaced)).foregroundStyle(VoltPaper.mutedFg)
        }
    }

    private func legendChip(_ e: Entry) -> some View {
        HStack(spacing: 4) {
            Circle().fill(e.color).frame(width: 6, height: 6)
            Text(e.symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(VoltPaper.mutedFg)
        }
    }
}

#endif
