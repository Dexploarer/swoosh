// DetourSetupInsightCharts.swift — compact setup state charts (0.5A)

import SwiftUI

struct DetourSetupInsightChartPanel: View {
    let summary: DetourSetupCapabilitySummary

    var body: some View {
        if summary.chartPoints.isEmpty {
            Text("Setup checks will appear here after Detour scans this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding()
                .accessibilityLabel("No setup chart data yet")
        } else {
            DetourSetupInsightChart2D(points: summary.chartPoints)
        }
    }
}

private struct DetourSetupInsightChart2D: View {
    let points: [DetourSetupInsightChartPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Setup status")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(accessibilitySummary)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(0.54))
            }
            ForEach(points) { point in
                HStack(spacing: 10) {
                    Text(point.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule()
                                .fill(color(for: point.status))
                                .frame(width: barWidth(point, available: geometry.size.width))
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(point.value))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        points.map { "\($0.label): \(Int($0.value))" }.joined(separator: ", ")
    }

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 1, 1)
    }

    private func barWidth(_ point: DetourSetupInsightChartPoint, available: CGFloat) -> CGFloat {
        let fraction = point.value / maxValue
        return max(point.value > 0 ? 6 : 0, available * CGFloat(fraction))
    }

    private func color(for status: DetourSetupInsightStatus?) -> Color {
        switch status {
        case .verified, .using:
            return .green
        case .selected, .pending:
            return .blue
        case .failed, .blocked, .needsPermission, .needsConfiguration:
            return .orange
        case .removed:
            return .secondary
        case .unknown, nil:
            return .gray
        }
    }
}
