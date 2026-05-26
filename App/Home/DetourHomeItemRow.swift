// DetourHomeItemRow.swift — Detour setup item row for the desktop workspace (0.5A)

import SwiftUI

struct DetourHomeItemRow: View {
    let item: DetourSetupInsightItem
    let action: (DetourSetupInsightAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            statusGlyph
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    DetourHomeStatusPill(status: item.status)
                }
                Text(item.subtitle ?? item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                metadata
                if !item.actions.isEmpty {
                    actionButtons
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusGlyph: some View {
        Image(systemName: iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(statusColor)
            .frame(width: 30, height: 30)
            .background(statusColor.opacity(0.14), in: Circle())
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            DetourHomeTinyLabel(text: item.owner.label, systemImage: "person.crop.circle")
            if let source = item.sourceLabel {
                DetourHomeTinyLabel(text: source, systemImage: "folder")
            }
            if let health = item.health {
                DetourHomeTinyLabel(text: health.state.label, systemImage: "heart.text.square")
            }
        }
        .lineLimit(1)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(item.actions, id: \.kind.rawValue) { itemAction in
                Button(itemAction.title) {
                    action(itemAction)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var iconName: String {
        switch item.status {
        case .verified, .using: "checkmark"
        case .selected, .pending: "clock"
        case .failed, .blocked: "exclamationmark"
        case .needsPermission: "lock"
        case .needsConfiguration: "wrench.and.screwdriver"
        case .removed: "minus"
        case .unknown: "questionmark"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .verified, .using: .green
        case .selected, .pending: .blue
        case .failed, .blocked, .needsPermission, .needsConfiguration: .orange
        case .removed: .secondary
        case .unknown: .gray
        }
    }
}

struct DetourHomeStatusPill: View {
    let status: DetourSetupInsightStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .verified, .using: .green
        case .selected, .pending: .blue
        case .failed, .blocked, .needsPermission, .needsConfiguration: .orange
        case .removed: .secondary
        case .unknown: .gray
        }
    }
}

private struct DetourHomeTinyLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
