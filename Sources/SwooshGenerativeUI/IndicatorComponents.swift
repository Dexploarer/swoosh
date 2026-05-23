// SwooshGenerativeUI/IndicatorComponents.swift — Built-in indicator component views (0.4A)

import SwiftUI

struct UIStatusChipView: View {
    let label: String
    let tint: String
    let systemImage: String?

    var body: some View {
        let color = resolveTint(tint)
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct UIBadgeView: View {
    let label: String
    let count: Int?
    let tint: String?

    var body: some View {
        let color = resolveTint(tint ?? "accent")
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(color))
            }
        }
    }
}

struct UIProgressView: View {
    let value: Double
    let label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SwiftUI.ProgressView(value: max(0, min(1, value)))
                .progressViewStyle(.linear)
        }
    }
}

struct UIMeterView: View {
    let value: Double
    let range: ClosedRangePair
    let label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let bounds = meterBounds(value: value, range: range)
            Gauge(value: bounds.value, in: bounds.lower...bounds.upper) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
        }
    }
}

struct UIMeterBounds: Equatable, Sendable {
    let lower: Double
    let upper: Double
    let value: Double
}

func meterBounds(value: Double, range: ClosedRangePair) -> UIMeterBounds {
    let lower = min(range.lower, range.upper)
    let upper = max(range.lower, range.upper)
    guard lower.isFinite, upper.isFinite, lower < upper else {
        let fallback = value.isFinite ? value : 0
        return UIMeterBounds(lower: 0, upper: 1, value: min(max(fallback, 0), 1))
    }
    let safeValue = value.isFinite ? value : lower
    return UIMeterBounds(lower: lower, upper: upper, value: min(max(safeValue, lower), upper))
}

struct UILoadingDotsView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .frame(width: 28, height: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
