// SwooshWidgets/Charts/UsageChartViews.swift — SwiftUI Charts for usage visualization
//
// Rich charts for provider usage, cost tracking, and system metrics.
// Uses the native SwiftUI Charts framework.

import SwiftUI
import Charts
import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Data models for charts
// ═══════════════════════════════════════════════════════════════════

/// A single usage data point.
public struct UsageDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let provider: String
    public let timestamp: Date
    public let value: Double
    public let category: String    // "requests", "tokens", "cost"

    public init(provider: String, timestamp: Date, value: Double, category: String) {
        self.provider = provider
        self.timestamp = timestamp
        self.value = value
        self.category = category
    }
}

/// Provider cost entry.
public struct CostEntry: Identifiable, Sendable {
    public let id = UUID()
    public let provider: String
    public let amount: Double
    public let color: Color

    public init(provider: String, amount: Double, color: Color) {
        self.provider = provider
        self.amount = amount
        self.color = color
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Usage over time chart (area)
// ═══════════════════════════════════════════════════════════════════

/// Area chart showing usage over time per provider.
public struct UsageOverTimeChart: View {
    let data: [UsageDataPoint]
    let title: String

    public init(data: [UsageDataPoint], title: String = "Usage") {
        self.data = data
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Chart(data) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(by: .value("Provider", point.provider))
                .interpolationMethod(.catmullRom)
                .opacity(0.3)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(by: .value("Provider", point.provider))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartForegroundStyleScale([
                "OpenAI": Color.cyan,
                "Anthropic": Color.orange,
                "Gemini": Color.blue,
                "DeepSeek": Color.green,
                "Groq": Color.purple,
            ])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                }
            }
            .chartYAxis {
                AxisMarks {
                    AxisValueLabel()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                }
            }
            .frame(height: 180)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Cost breakdown chart (donut)
// ═══════════════════════════════════════════════════════════════════

/// Donut chart showing cost distribution across providers.
public struct CostBreakdownChart: View {
    let entries: [CostEntry]
    let totalLabel: String

    public init(entries: [CostEntry], totalLabel: String = "") {
        self.entries = entries
        self.totalLabel = totalLabel
    }

    public var body: some View {
        VStack(spacing: 8) {
            Text("Cost Breakdown")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Chart(entries) { entry in
                SectorMark(
                    angle: .value("Cost", entry.amount),
                    innerRadius: .ratio(0.65),
                    angularInset: 1.5
                )
                .foregroundStyle(entry.color)
                .cornerRadius(3)
                .annotation(position: .overlay) {
                    if entry.amount > 0.1 {
                        Text(String(format: "$%.2f", entry.amount))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartBackground { proxy in
                GeometryReader { geo in
                    let frame = geo[proxy.plotFrame!]
                    VStack(spacing: 2) {
                        Text("Total")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(totalLabel.isEmpty ? totalString : totalLabel)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(height: 180)

            // Legend
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 4) {
                ForEach(entries) { entry in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 6, height: 6)
                        Text(entry.provider)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var totalString: String {
        String(format: "$%.2f", entries.reduce(0) { $0 + $1.amount })
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider usage bar chart
// ═══════════════════════════════════════════════════════════════════

/// Horizontal bar chart comparing provider usage percentages.
public struct ProviderUsageBarChart: View {
    let data: [(provider: String, usage: Double, color: Color)]

    public init(data: [(provider: String, usage: Double, color: Color)]) {
        self.data = data
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider Usage")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Usage", item.usage),
                        y: .value("Provider", item.provider)
                    )
                    .foregroundStyle(item.color.gradient)
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        Text("\(Int(item.usage * 100))%")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // Budget line at 80%
                RuleMark(x: .value("Budget", 0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("80%")
                            .font(.system(size: 8))
                            .foregroundStyle(.red.opacity(0.7))
                    }
            }
            .chartXScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                    AxisValueLabel {
                        Text("\(Int((value.as(Double.self) ?? 0) * 100))%")
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                }
            }
            .frame(height: CGFloat(data.count * 36 + 20))
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sample data generators
// ═══════════════════════════════════════════════════════════════════

public enum SampleChartData {
    /// Generate sample usage-over-time data.
    public static func usageOverTime() -> [UsageDataPoint] {
        let providers = ["OpenAI", "Anthropic", "Gemini"]
        let now = Date()
        var points: [UsageDataPoint] = []

        for provider in providers {
            for i in stride(from: -24, through: 0, by: 1) {
                let ts = now.addingTimeInterval(TimeInterval(i * 3600))
                let base: Double = provider == "OpenAI" ? 45 : provider == "Anthropic" ? 30 : 15
                let jitter = Double.random(in: -10...10)
                points.append(UsageDataPoint(
                    provider: provider,
                    timestamp: ts,
                    value: max(0, base + jitter + Double(i + 24) * 1.5),
                    category: "requests"
                ))
            }
        }

        return points
    }

    /// Generate sample cost entries.
    public static func costBreakdown() -> [CostEntry] {
        [
            CostEntry(provider: "OpenAI", amount: 4.23, color: .cyan),
            CostEntry(provider: "Anthropic", amount: 8.10, color: .orange),
            CostEntry(provider: "Gemini", amount: 0.95, color: .blue),
            CostEntry(provider: "DeepSeek", amount: 1.05, color: .green),
            CostEntry(provider: "Groq", amount: 0.15, color: .purple),
        ]
    }

    /// Generate sample provider usage bars.
    public static func providerUsage() -> [(provider: String, usage: Double, color: Color)] {
        [
            ("OpenAI", 0.45, .cyan),
            ("Anthropic", 0.72, .orange),
            ("Gemini", 0.18, .blue),
            ("DeepSeek", 0.90, .green),
            ("Groq", 0.30, .purple),
        ]
    }
}
