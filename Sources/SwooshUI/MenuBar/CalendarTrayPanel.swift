// SwooshUI/MenuBar/CalendarTrayPanel.swift — 0.4A Detour Calendar panel
//
// A CUSTOM, agent-managed calendar — NOT Apple Calendar / EventKit, and NOT
// SwooshScout's aggregate CalendarSource. Upcoming events are read over the
// daemon RPC (`SwooshDaemonClient.client().calendarEvents()`); the agent
// creates/moves/clears them via its calendar tools (ask Detour in Chat).
// Cyan accent. Zero Apple-calendar imports by design.

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshGenerativeUI

struct CalendarTrayPanel: View {
    @State private var events: [CalendarEventSummary] = []
    @State private var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        TrayPanelScaffold(
            title: "Calendar",
            subtitle: "Your agent-managed schedule",
            icon: "calendar",
            accent: .cyan
        ) {
            VStack(alignment: .leading, spacing: 12) {
                switch phase {
                case .loading:
                    TrayStatusRow(icon: "calendar", message: "Loading your calendar…", spinning: true)
                case .failed(let msg):
                    TrayStatusRow(icon: "exclamationmark.triangle.fill", message: msg)
                case .loaded where events.isEmpty:
                    emptyState
                case .loaded:
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
                askHint
            }
        }
        .task { await load() }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NeonAccent.cyan.color)
                Text("Nothing scheduled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Spacer(minLength: 0)
            }
            Text("Your Detour calendar is clear. Ask Detour in Chat to add something.")
                .font(.system(size: 10.5))
                .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonTile(.cyan, state: .idle, shape: .card)
    }

    private func eventRow(_ event: CalendarEventSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 1) {
                Text(Self.dayFormatter.string(from: event.start))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text(Self.dayNumberFormatter.string(from: event.start))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(NeonAccent.cyan.color)
            }
            .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .lineLimit(1)
                Text(Self.timeRange(event))
                    .font(.system(size: 10))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 9.5))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .neonTile(.cyan, state: .idle, shape: .card)
    }

    private var askHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 10, weight: .semibold))
            Text("Ask Detour in Chat to schedule, move, or clear events.")
                .font(.system(size: 9.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        .padding(.top, 2)
    }

    // MARK: - Formatting

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private static func timeRange(_ event: CalendarEventSummary) -> String {
        "\(timeFormatter.string(from: event.start)) – \(timeFormatter.string(from: event.end))"
    }

    // MARK: - Data

    private func load() async {
        phase = .loading
        guard let client = SwooshDaemonClient.client() else {
            phase = .failed("Detour runtime offline.")
            return
        }
        do {
            events = try await client.calendarEvents().events
            phase = .loaded
        } catch {
            phase = .failed("Couldn't load the calendar.")
        }
    }
}

#endif
