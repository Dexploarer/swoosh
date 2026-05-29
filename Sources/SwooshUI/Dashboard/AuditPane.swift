// SwooshUI/Dashboard/AuditPane.swift — Live audit log — 0.9V
//
// Fetches from /api/audit and displays a real-time event timeline
// with tool call details, success/failure indicators, and session IDs.

import SwiftUI
import SwooshGenerativeUI
import SwooshClient

public struct AuditPane: View {
    @State private var events: [AuditEventSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedKindFilter: String?

    public init() {}

    private var kinds: [String] {
        Array(Set(events.map(\.kind))).sorted()
    }

    private var filteredEvents: [AuditEventSummary] {
        guard let filter = selectedKindFilter else { return events }
        return events.filter { $0.kind == filter }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            kindFilter
            Divider().background(SwooshNeonTokens.Line.rule)
            if isLoading && events.isEmpty {
                loadingView
            } else if events.isEmpty {
                emptyView
            } else {
                eventList
            }
        }
        .background(SwooshNeonTokens.Canvas.bg)
        .task { await loadAudit() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audit Log")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text("\(events.count) events")
                    .font(.system(size: 12))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
            Spacer()
            Button {
                Task { await loadAudit() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - Filter

    private var kindFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("All", id: nil)
                ForEach(kinds, id: \.self) { kind in
                    filterChip(kind, id: kind)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(_ label: String, id: String?) -> some View {
        let selected = selectedKindFilter == id
        return Button {
            selectedKindFilter = id
        } label: {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? SwooshNeonTokens.Accent.cyan : SwooshNeonTokens.Canvas.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? SwooshNeonTokens.Accent.cyan.opacity(0.12) : Color.white.opacity(0.03))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? SwooshNeonTokens.Accent.cyan.opacity(0.3) : SwooshNeonTokens.Line.rule,
                    lineWidth: 0.5
                ))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Event list

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredEvents) { event in
                    eventRow(event)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func eventRow(_ event: AuditEventSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.success ? VoltPaper.accent : VoltPaper.destructive)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
                .shadow(color: (event.success ? VoltPaper.accent : VoltPaper.destructive).opacity(0.5), radius: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.kind)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                    if let toolName = event.toolName {
                        Text(toolName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    }
                    Spacer()
                    Text(formatDate(event.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                }
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(VoltPaper.foreground.opacity(0.015))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading audit events…")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3.opacity(0.4))
            Text("No audit events yet")
                .font(.system(size: 14))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            Text("Events will appear as the agent processes requests.")
                .font(.system(size: 12))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Network

    private func loadAudit() async {
        guard let client = SwooshDaemonClient.client() else {
            errorMessage = "Daemon not reachable."
            isLoading = false
            return
        }
        isLoading = true
        do {
            let response = try await client.audit()
            events = response.events
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}


