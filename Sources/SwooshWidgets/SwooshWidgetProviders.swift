// SwooshWidgets/SwooshWidgetProviders.swift — WidgetKit timeline providers
//
// These providers feed data to the widget extension.
// The main Swoosh app writes SwooshWidgetSnapshot to App Group UserDefaults;
// the widget reads it and renders the appropriate view.

import SwiftUI
import WidgetKit

// ═══════════════════════════════════════════════════════════════════
// MARK: - Timeline entry
// ═══════════════════════════════════════════════════════════════════

public struct SwooshWidgetEntry: TimelineEntry {
    public let date: Date
    public let snapshot: SwooshWidgetSnapshot

    public init(date: Date, snapshot: SwooshWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared timeline provider logic
// ═══════════════════════════════════════════════════════════════════

public struct SwooshTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> SwooshWidgetEntry {
        SwooshWidgetEntry(date: Date(), snapshot: .preview)
    }

    public func getSnapshot(in context: Context, completion: @escaping (SwooshWidgetEntry) -> Void) {
        let snapshot = SwooshWidgetSnapshot.load() ?? .preview
        completion(SwooshWidgetEntry(date: Date(), snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SwooshWidgetEntry>) -> Void) {
        let snapshot = SwooshWidgetSnapshot.load() ?? .preview
        let entry = SwooshWidgetEntry(date: Date(), snapshot: snapshot)

        // Refresh every 2 minutes
        let nextUpdate = Date().addingTimeInterval(120)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Widget definitions
// ═══════════════════════════════════════════════════════════════════

/// Small provider usage widget — like a compact stocks ticker.
public struct SwooshProviderWidget: Widget {
    public let kind: String = "SwooshProviderWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SwooshTimelineProvider()) { entry in
            ProviderUsageSmallView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Provider Status")
        .description("Your AI provider usage at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

/// Medium command center widget — providers + stats split view.
public struct SwooshCommandWidget: Widget {
    public let kind: String = "SwooshCommandWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SwooshTimelineProvider()) { entry in
            CommandCenterMediumView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Command Center")
        .description("Providers, agents, approvals, and costs.")
        .supportedFamilies([.systemMedium])
    }
}

/// Large full dashboard widget — everything in one view.
public struct SwooshDashboardWidget: Widget {
    public let kind: String = "SwooshDashboardWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SwooshTimelineProvider()) { entry in
            DashboardLargeView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Dashboard")
        .description("Full Swoosh command center with all providers.")
        .supportedFamilies([.systemLarge])
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Widget bundle
// ═══════════════════════════════════════════════════════════════════

/// The complete widget bundle for Swoosh.
/// In the widget extension target, use: `@main struct SwooshWidgetBundle: WidgetBundle { ... }`
public struct SwooshWidgetCollection: WidgetBundle {
    public init() {}

    public var body: some Widget {
        SwooshProviderWidget()
        SwooshCommandWidget()
        SwooshDashboardWidget()
    }
}
