// SwooshUI/DashboardPanes/DashboardPanePrimitives.swift — Shared dashboard pane building blocks — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

import SwooshGenerativeUI
import SwooshModels
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shared building blocks
// ═══════════════════════════════════════════════════════════════════

struct PaneHeader: View {
    @Environment(\.swooshTheme) var theme
    let title: String
    let icon: String
    let subtitle: String?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.accent.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
        .padding(.bottom, 4)
    }
}

struct PaneCard<Content: View>: View {
    @Environment(\.swooshTheme) var theme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.textPrimary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.textPrimary.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

struct StatBadge: View {
    @Environment(\.swooshTheme) var theme
    let value: String
    let label: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.textPrimary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                )
        )
    }
}

struct OfflineBanner: View {
    @Environment(\.swooshTheme) var theme
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text(reason)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.85))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}

struct ListRow: View {
    @Environment(\.swooshTheme) var theme
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    let trailing: String?
    var trailingTint: Color = .secondary
    var onTap: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.58))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(trailingTint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                .fill(hovering && onTap != nil ? theme.textPrimary.opacity(0.04) : Color.clear)
        )

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            content
        }
    }
}

// Generic scaffolding all panes share.
struct DashboardPane<Content: View>: View {
    @Environment(\.swooshTheme) var theme
    let title: String
    let icon: String
    let subtitle: String?
    var headerTrailing: AnyView? = nil
    let content: () -> Content

    init(title: String, icon: String, subtitle: String? = nil,
         headerTrailing: AnyView? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(title: title, icon: icon, subtitle: subtitle, trailing: headerTrailing)
                content()
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .background(SwooshNeonTokens.Canvas.bg)
    }
}

func makeClient() -> SwooshAPIClient? {
    SwooshDaemonClient.client()
}

#endif
