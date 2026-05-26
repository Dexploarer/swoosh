// DetourHomeInboxPanel.swift — universal inbox surface for Detour home (0.5A)

import SwiftUI

struct DetourHomeInboxPanel: View {
    @ObservedObject var inbox: DetourHomeInboxModel
    let reviewSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if inbox.items.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(inbox.items.prefix(6)) { item in
                        DetourHomeInboxRow(item: item)
                    }
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.indigo, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("Universal inbox")
                    .font(.title3.weight(.semibold))
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                DetourHomeStatusBadge(label: inbox.state.label, tint: tint)
                Button {
                    inbox.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyTitle)
                .font(.headline)
            Text(emptyDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Refresh inbox") {
                    inbox.refresh()
                }
                .buttonStyle(.borderedProminent)
                Button("Connect channels") {
                    reviewSetup()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryText: String {
        if case .failed(let message) = inbox.state {
            return message
        }
        let sources = inbox.connectedSources.isEmpty ? "default chat" : inbox.connectedSources.joined(separator: ", ")
        if inbox.pendingCount > 0 {
            return "\(inbox.pendingCount) items need approval. Reading \(sources)."
        }
        return "Shows Detour replies, your messages, and pending actions from \(sources)."
    }

    private var emptyTitle: String {
        switch inbox.state {
        case .loading:
            "Checking messages..."
        case .failed:
            "Inbox is offline."
        default:
            "No agent messages yet."
        }
    }

    private var emptyDetail: String {
        if case .failed(let message) = inbox.state {
            return message
        }
        return "Once Detour chats, replies, or asks for approval, those items appear here."
    }

    private var tint: Color {
        if case .failed = inbox.state {
            return .orange
        }
        return inbox.pendingCount > 0 ? .orange : .green
    }
}

private struct DetourHomeInboxRow: View {
    let item: DetourHomeInboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                    Spacer()
                    Text(item.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text(item.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(item.source, systemImage: "point.3.connected.trianglepath.dotted")
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(item.createdAt, style: .time)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        switch item.kind {
        case .incoming: "message"
        case .reply: "paperplane"
        case .approval: "checkmark.shield"
        case .activity: item.healthy ? "bolt.horizontal" : "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch item.kind {
        case .incoming: .blue
        case .reply: .green
        case .approval: .orange
        case .activity: item.healthy ? .secondary : .orange
        }
    }
}
