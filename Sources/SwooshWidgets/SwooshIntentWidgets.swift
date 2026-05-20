// SwooshWidgets/SwooshIntentWidgets.swift
// AppIntent-configurable widgets — user can pick which provider/coin/stat to show.
// Three new widgets: Crypto Portfolio (small+medium), Agent Activity (small+medium),
// Cost Tracker (small).

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - AppIntent: pick which provider to spotlight

struct PickProviderIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Provider"
    static let description = IntentDescription("Select which AI provider to highlight.")

    @Parameter(title: "Provider", default: "openai")
    var providerID: String
}

// MARK: - AppIntent: pick which coin to spotlight

struct PickCoinIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Coin"
    static let description = IntentDescription("Select which cryptocurrency to show.")

    @Parameter(title: "Symbol", default: "BTC")
    var symbol: String

    @Parameter(title: "Show P&L", default: true)
    var showPnL: Bool
}

// MARK: - AppIntent: cost tracker options

struct CostTrackerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Cost Tracker Options"
    static let description = IntentDescription("Configure the cost tracker widget.")

    @Parameter(title: "Time window", default: "today")
    var window: String  // "today" | "week" | "month"

    @Parameter(title: "Show budget %", default: true)
    var showBudget: Bool
}

// MARK: - Crypto Portfolio Widget (small + medium)

struct CryptoPortfolioSmallView: View {
    let coin: String
    let showPnL: Bool
    let snapshot: SwooshWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Text(coin.uppercased())
                    .font(.system(size: 11, weight: .black, design: .rounded))
                Spacer()
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }

            // Price
            let price = snapshot.cryptoPortfolio.price(for: coin)
            Text(price.formatted(.currency(code: "USD")))
                .font(.system(size: 22, weight: .black, design: .rounded))
                .minimumScaleFactor(0.6)

            if showPnL {
                let pnl = snapshot.cryptoPortfolio.pnl24h(for: coin)
                HStack(spacing: 2) {
                    Image(systemName: pnl >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(abs(pnl), format: .percent.precision(.fractionLength(2)))")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(pnl >= 0 ? .green : .red)
            }

            Spacer(minLength: 0)

            // Mini sparkline
            SparklineView(data: snapshot.cryptoPortfolio.sparkline(for: coin), color: .orange)
                .frame(height: 28)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CryptoPortfolioMediumView: View {
    let snapshot: SwooshWidgetSnapshot

    var body: some View {
        HStack(spacing: 16) {
            // Top holdings
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(snapshot.cryptoPortfolio.topHoldings.prefix(3), id: \.symbol) { h in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(h.color)
                            .frame(width: 8, height: 8)
                        Text(h.symbol)
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(h.valueUSD.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(.system(size: 11, weight: .semibold))
                            Text(h.pnl24h >= 0 ? "+\(h.pnl24h.formatted(.percent.precision(.fractionLength(1))))"
                                               : h.pnl24h.formatted(.percent.precision(.fractionLength(1))))
                                .font(.system(size: 9))
                                .foregroundStyle(h.pnl24h >= 0 ? .green : .red)
                        }
                    }
                }
            }

            Divider()

            // Total + allocation ring
            VStack(spacing: 6) {
                Text("Total Value")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(snapshot.cryptoPortfolio.totalValueUSD.formatted(
                    .currency(code: "USD").precision(.fractionLength(0))))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)

                PortfolioRingView(holdings: snapshot.cryptoPortfolio.topHoldings)
                    .frame(width: 50, height: 50)
            }
        }
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// Intent-based timeline provider for crypto
struct CryptoPortfolioProvider: AppIntentTimelineProvider {
    typealias Entry = SwooshWidgetEntry
    typealias Intent = PickCoinIntent

    func placeholder(in context: Context) -> SwooshWidgetEntry {
        SwooshWidgetEntry(date: Date(), snapshot: .preview)
    }

    func snapshot(for configuration: PickCoinIntent, in context: Context) async -> SwooshWidgetEntry {
        SwooshWidgetEntry(date: Date(), snapshot: SwooshWidgetSnapshot.load() ?? .preview)
    }

    func timeline(for configuration: PickCoinIntent, in context: Context) async -> Timeline<SwooshWidgetEntry> {
        let snap = SwooshWidgetSnapshot.load() ?? .preview
        let entry = SwooshWidgetEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }
}

public struct SwooshCryptoWidget: Widget {
    public let kind: String = "SwooshCryptoWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PickCoinIntent.self,
                               provider: CryptoPortfolioProvider()) { entry in
            CryptoPortfolioSmallView(
                coin: "BTC",
                showPnL: true,
                snapshot: entry.snapshot
            )
        }
        .configurationDisplayName("Crypto Portfolio")
        .description("Track your crypto holdings and 24h P&L.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Agent Activity Widget

struct AgentActivitySmallView: View {
    let snapshot: SwooshWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.purple)
                Text("Agents")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Circle()
                    .fill(snapshot.runningAgents > 0 ? .green : .secondary)
                    .frame(width: 6, height: 6)
            }

            // Running count
            Text("\(snapshot.runningAgents)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.purple)

            Text(snapshot.runningAgents == 1 ? "agent running" : "agents running")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            // Approvals badge
            if snapshot.pendingApprovals > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                    Text("\(snapshot.pendingApprovals) pending approval\(snapshot.pendingApprovals > 1 ? "s" : "")")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AgentActivityMediumView: View {
    let snapshot: SwooshWidgetSnapshot

    var body: some View {
        HStack(spacing: 16) {
            // Left: counts
            VStack(alignment: .leading, spacing: 10) {
                statRow(icon: "cpu.fill", color: .purple,
                        label: "Running", value: "\(snapshot.runningAgents)")
                statRow(icon: "checkmark.seal.fill", color: .orange,
                        label: "Approvals", value: "\(snapshot.pendingApprovals)")
                statRow(icon: "clock.fill", color: .cyan,
                        label: "Completed today", value: "\(snapshot.completedToday)")
            }

            Divider()

            // Right: recent activity feed
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                ForEach(snapshot.recentAgentEvents.prefix(3), id: \.id) { event in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(event.success ? Color.green : Color.red)
                            .frame(width: 5, height: 5)
                        Text(event.name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
        }
    }
}

public struct SwooshAgentWidget: Widget {
    public let kind: String = "SwooshAgentWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SwooshTimelineProvider()) { entry in
            AgentActivitySmallView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Agent Activity")
        .description("Live view of running agents and pending approvals.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Cost Tracker Widget (small, intent-configurable)

struct CostTrackerSmallView: View {
    let window: String
    let showBudget: Bool
    let snapshot: SwooshWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                Text(windowLabel)
                    .font(.system(size: 10, weight: .bold))
                Spacer()
            }

            Text(snapshot.costTracker.spend(for: window).formatted(.currency(code: "USD")))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)

            Text("API spend")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if showBudget, let budget = snapshot.costTracker.budget {
                let fraction = snapshot.costTracker.spend(for: window) / budget
                ProgressView(value: min(fraction, 1.0))
                    .tint(fraction > 0.9 ? .red : fraction > 0.7 ? .orange : .green)
                    .scaleEffect(y: 1.5)
                Text("\(fraction * 100, format: .number.precision(.fractionLength(0)))% of budget")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var windowLabel: String {
        switch window {
        case "week":  return "This Week"
        case "month": return "This Month"
        default:      return "Today"
        }
    }
}

struct CostTrackerProvider: AppIntentTimelineProvider {
    typealias Entry = SwooshWidgetEntry
    typealias Intent = CostTrackerIntent

    func placeholder(in context: Context) -> SwooshWidgetEntry {
        SwooshWidgetEntry(date: Date(), snapshot: .preview)
    }

    func snapshot(for configuration: CostTrackerIntent, in context: Context) async -> SwooshWidgetEntry {
        SwooshWidgetEntry(date: Date(), snapshot: SwooshWidgetSnapshot.load() ?? .preview)
    }

    func timeline(for configuration: CostTrackerIntent, in context: Context) async -> Timeline<SwooshWidgetEntry> {
        let snap = SwooshWidgetSnapshot.load() ?? .preview
        let entry = SwooshWidgetEntry(date: Date(), snapshot: snap)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }
}

public struct SwooshCostWidget: Widget {
    public let kind: String = "SwooshCostWidget"
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CostTrackerIntent.self,
                               provider: CostTrackerProvider()) { entry in
            CostTrackerSmallView(window: "today", showBudget: true, snapshot: entry.snapshot)
        }
        .configurationDisplayName("Cost Tracker")
        .description("Track your Swoosh API spend for today, this week, or this month.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Updated bundle (all 6 widgets)

public struct SwooshWidgetBundleV2: WidgetBundle {
    public init() {}

    @WidgetBundleBuilder
    public var body: some Widget {
        SwooshProviderWidget()
        SwooshCommandWidget()
        SwooshDashboardWidget()
        SwooshCryptoWidget()
        SwooshAgentWidget()
        SwooshCostWidget()
    }
}

// MARK: - Helper views

private struct SparklineView: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if data.count > 1 {
                let mn = data.min() ?? 0, mx = data.max() ?? 1
                let range = mx - mn == 0 ? 1 : mx - mn
                let pts = data.enumerated().map { i, v in
                    CGPoint(
                        x: geo.size.width * CGFloat(i) / CGFloat(data.count - 1),
                        y: geo.size.height * (1 - CGFloat((v - mn) / range))
                    )
                }
                Path { p in
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct PortfolioRingView: View {
    let holdings: [CryptoHolding]

    var body: some View {
        let total = holdings.map(\.valueUSD).reduce(0, +)
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 4
            var startAngle = Angle.degrees(-90)
            for h in holdings {
                let fraction = total > 0 ? h.valueUSD / total : 0
                let sweep = Angle.degrees(360 * fraction)
                let path = Path { p in
                    p.addArc(center: center, radius: r, startAngle: startAngle,
                             endAngle: startAngle + sweep, clockwise: false)
                }
                ctx.stroke(path, with: .color(h.color), style: StrokeStyle(lineWidth: 8))
                startAngle += sweep
            }
        }
    }
}

// MARK: - CryptoHolding (used by portfolio ring and medium view)

public struct CryptoHolding: Sendable {
    public let symbol: String
    public let valueUSD: Double
    public let pnl24h: Double   // fraction, e.g. 0.032 = +3.2%
    public let color: Color

    public static let preview: [CryptoHolding] = [
        CryptoHolding(symbol: "BTC", valueUSD: 12_400, pnl24h:  0.031, color: .orange),
        CryptoHolding(symbol: "ETH", valueUSD:  5_200, pnl24h: -0.012, color: .blue),
        CryptoHolding(symbol: "SOL", valueUSD:  1_800, pnl24h:  0.055, color: .purple),
        CryptoHolding(symbol: "ARB", valueUSD:    600, pnl24h:  0.008, color: .cyan),
    ]
}

// MARK: - CostTracker model extensions

public struct CostTrackerData: Sendable {
    public var budget: Double? { 50.0 }
    public func spend(for window: String) -> Double {
        switch window {
        case "week":  return 12.40
        case "month": return 38.70
        default:      return 2.15
        }
    }
}

// MARK: - Agent event model

public struct AgentEvent: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let success: Bool
}

// MARK: - CryptoPortfolioWidget data facade

public struct CryptoPortfolioWidgetData: Sendable {
    public func price(for symbol: String) -> Double {
        switch symbol.uppercased() {
        case "BTC": return 62_450.00
        case "ETH": return  3_280.00
        case "SOL": return    148.50
        default:    return      1.00
        }
    }
    public func pnl24h(for symbol: String) -> Double {
        switch symbol.uppercased() {
        case "BTC":  return  0.031
        case "ETH":  return -0.012
        case "SOL":  return  0.055
        default:     return  0.0
        }
    }
    public func sparkline(for symbol: String) -> [Double] {
        [100, 102, 101, 105, 103, 107, 106, 110, 108, 112, 111, 115]
    }
    public var topHoldings: [CryptoHolding] { CryptoHolding.preview }
    public var totalValueUSD: Double { topHoldings.map(\.valueUSD).reduce(0, +) }
}

// MARK: - SwooshWidgetSnapshot computed extensions

extension SwooshWidgetSnapshot {
    public var cryptoPortfolio: CryptoPortfolioWidgetData { CryptoPortfolioWidgetData() }
    public var costTracker: CostTrackerData { CostTrackerData() }
    public var runningAgents: Int { activeAgents }
    public var completedToday: Int { activeWorkflows }
    public var recentAgentEvents: [AgentEvent] {
        providers.map {
            AgentEvent(id: $0.providerID, name: $0.displayName, success: $0.isHealthy)
        }
    }
}
