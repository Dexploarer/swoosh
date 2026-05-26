// DetourHomeCryptoComponents.swift — small wallet and social SwiftUI pieces (0.5A)

import SwiftUI

struct DetourWalletBarChart: View {
    let title: String
    let emptyText: String
    let points: [DetourWalletChartPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if points.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            } else {
                ForEach(points) { point in
                    HStack(spacing: 10) {
                        Text(point.label)
                            .font(.caption.weight(.semibold))
                            .frame(width: 92, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule()
                                    .fill(point.tint.color)
                                    .frame(width: width(point, available: geometry.size.width))
                            }
                        }
                        .frame(height: 9)
                        Text("\(Int(point.value))")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(accessibilitySummary)
    }

    private var maxValue: Double {
        max(points.map(\.value).max() ?? 1, 1)
    }

    private var accessibilitySummary: String {
        points.isEmpty ? emptyText : points.map { "\($0.label): \(Int($0.value))" }.joined(separator: ", ")
    }

    private func width(_ point: DetourWalletChartPoint, available: CGFloat) -> CGFloat {
        let fraction = point.value / maxValue
        return max(point.value > 0 ? 8 : 0, available * CGFloat(fraction))
    }
}

struct DetourHomeMiniMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DetourHomeStatusBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct DetourHomeChainDot: View {
    let chain: String

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 12, height: 12)
    }

    private var tint: Color {
        switch chain.lowercased() {
        case "solana":
            .purple
        case "bnb":
            .yellow
        case "base":
            .blue
        case "ethereum":
            .indigo
        default:
            .green
        }
    }
}

struct DetourSocialChip: View {
    let item: DetourSetupInsightItem

    var body: some View {
        Text(item.title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        item.status.needsAttention ? .orange : .green
    }
}

extension DetourWalletChartTint {
    var color: Color {
        switch self {
        case .blue:
            .blue
        case .green:
            .green
        case .indigo:
            .indigo
        case .orange:
            .orange
        case .purple:
            .purple
        case .secondary:
            .secondary
        case .yellow:
            .yellow
        }
    }
}
