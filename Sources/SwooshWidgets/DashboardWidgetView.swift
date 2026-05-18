// SwooshWidgets/DashboardWidgetView.swift — Full dashboard widget (large)
#if canImport(WidgetKit)
import WidgetKit
import SwiftUI

// MARK: - Full dashboard widget (large — like the news widget)
// ═══════════════════════════════════════════════════════════════════

/// Full provider dashboard. Fits systemLarge.
public struct DashboardLargeView: View {
    let snapshot: SwooshWidgetSnapshot

    public init(snapshot: SwooshWidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("Swoosh Command Center")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                statusPill
            }

            Divider().opacity(0.3)

            // Stats row
            HStack(spacing: 12) {
                QuickStat(icon: "hand.raised.fill", label: "Approvals",
                          value: "\(snapshot.pendingApprovals)",
                          color: snapshot.pendingApprovals > 0 ? .orange : .green)
                QuickStat(icon: "person.3.fill", label: "Agents",
                          value: "\(snapshot.activeAgents)", color: .cyan)
                QuickStat(icon: "arrow.triangle.branch", label: "Workflows",
                          value: "\(snapshot.activeWorkflows)", color: .purple)
                if let cost = snapshot.totalCost {
                    QuickStat(icon: "dollarsign.circle.fill", label: "Spend",
                              value: cost, color: .yellow)
                }
            }

            Divider().opacity(0.3)

            // Provider list
            Text("Providers")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            ForEach(snapshot.providers) { provider in
                DetailedProviderRow(provider: provider)
            }

            Spacer(minLength: 0)

            // Footer
            HStack {
                Text(snapshot.timestamp, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("ago")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(snapshot.systemStatus.rawValue.capitalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }

    private var statusColor: Color {
        switch snapshot.systemStatus {
        case .healthy:  return .green
        case .degraded: return .yellow
        case .offline:  return .red
        }
    }
}

/// Quick stat tile for the large widget.
struct QuickStat: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Detailed provider row for the large widget.
struct DetailedProviderRow: View {
    let provider: WidgetProviderStatus

    var body: some View {
        HStack(spacing: 8) {
            // Health dot
            Circle()
                .fill(provider.isHealthy ? .green : .red)
                .frame(width: 5, height: 5)

            // Name
            Text(provider.displayName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)

            // Usage bar
            if let pct = provider.usagePercent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(pct))
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 4)
            }

            // Source badge
            Text(provider.sourceKind)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))

            // Cost
            if let cost = provider.costLabel {
                Text(cost)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Reset timer
            if let reset = provider.resetLabel {
                Text(reset)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func barColor(_ pct: Double) -> Color {
        pct > 0.85 ? .red : pct > 0.6 ? .orange : .cyan
    }
}

#endif
