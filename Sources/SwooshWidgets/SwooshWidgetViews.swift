// SwooshWidgets/SwooshWidgetViews.swift — WidgetKit-compatible views
//
// These views are designed for macOS Notification Center widgets.
// Supports: systemSmall, systemMedium, systemLarge, systemExtraLarge.

import SwiftUI
import WidgetKit

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider usage widget (small — like the stocks widget)
// ═══════════════════════════════════════════════════════════════════

/// Shows top providers with usage bars. Fits systemSmall.
public struct ProviderUsageSmallView: View {
    let snapshot: SwooshWidgetSnapshot

    public init(snapshot: SwooshWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("Swoosh")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                statusDot
            }

            Divider().opacity(0.3)

            // Top 3 providers
            ForEach(Array(snapshot.providers.prefix(3))) { provider in
                MiniProviderRow(provider: provider)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
    }

    private var statusColor: Color {
        switch snapshot.systemStatus {
        case .healthy:  return .green
        case .degraded: return .yellow
        case .offline:  return .red
        }
    }
}

/// Compact provider row for small widget.
struct MiniProviderRow: View {
    let provider: WidgetProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(provider.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let label = provider.usageLabel {
                    Text(label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let pct = provider.usagePercent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.quaternary)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(barGradient(pct))
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func barGradient(_ pct: Double) -> LinearGradient {
        let color: Color = pct > 0.85 ? .red : pct > 0.6 ? .orange : .cyan
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Command center widget (medium — like the weather widget)
// ═══════════════════════════════════════════════════════════════════

/// Shows providers + system stats. Fits systemMedium.
public struct CommandCenterMediumView: View {
    let snapshot: SwooshWidgetSnapshot

    public init(snapshot: SwooshWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left: providers
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("Providers")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }

                ForEach(Array(snapshot.providers.prefix(4))) { provider in
                    MiniProviderRow(provider: provider)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)

            Divider().opacity(0.3)

            // Right: stats
            VStack(alignment: .leading, spacing: 8) {
                StatBadge(icon: "hand.raised.fill", label: "Approvals",
                          value: "\(snapshot.pendingApprovals)",
                          color: snapshot.pendingApprovals > 0 ? .orange : .green)

                StatBadge(icon: "person.3.fill", label: "Agents",
                          value: "\(snapshot.activeAgents)",
                          color: .cyan)

                StatBadge(icon: "square.grid.3x3.fill", label: "Board",
                          value: "\(snapshot.activeBoardCards)",
                          color: .purple)

                if let cost = snapshot.totalCost {
                    StatBadge(icon: "dollarsign.circle.fill", label: "Spend",
                              value: cost, color: .yellow)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// Stat badge for the medium widget right panel.
struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
