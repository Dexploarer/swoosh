// SwooshUI/MenuBar/MenuBarSectionViews.swift — Individual section content views
//
// Provider status, usage meters, and quick actions sections.

import SwiftUI
import SwooshSecrets

// ═══════════════════════════════════════════════════════════════════
// MARK: - Provider status section
// ═══════════════════════════════════════════════════════════════════

struct ProviderStatusSectionView: View {
    let statuses: [ProviderCredentialStatus]
    let maxItems: Int?
    let compact: Bool

    @Environment(\.swooshTheme) var theme

    private var visibleStatuses: [ProviderCredentialStatus] {
        if let max = maxItems { return Array(statuses.prefix(max)) }
        return statuses
    }

    var body: some View {
        if statuses.isEmpty {
            emptyState
        } else {
            VStack(spacing: compact ? 3 : 6) {
                ForEach(visibleStatuses) { status in
                    ProviderStatusRow(status: status, compact: compact)
                }

                if let max = maxItems, statuses.count > max {
                    Text("+\(statuses.count - max) more")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
            Text("No providers discovered")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
    }
}

// ── Provider row ──

struct ProviderStatusRow: View {
    let status: ProviderCredentialStatus
    let compact: Bool

    @Environment(\.swooshTheme) var theme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(status.isHealthy ? theme.success : theme.error)
                .frame(width: 6, height: 6)

            // Provider name
            Text(status.displayName)
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            // Source badge
            Text(sourceBadge)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.accent.opacity(0.12), in: Capsule())

            // Kind icon
            Image(systemName: kindIcon)
                .font(.system(size: 9))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, compact ? 2 : 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? theme.surface.opacity(0.3) : .clear)
        )
        .onHover { isHovered = $0 }
    }

    private var sourceBadge: String {
        switch status.source {
        case .environment:        return "ENV"
        case .configFile:         return "FILE"
        case .keychainThirdParty: return "KEY"
        case .browserCookie:      return "COOKIE"
        case .swooshKeychain:     return "SWOOSH"
        }
    }

    private var kindIcon: String {
        switch status.credentialKind {
        case .apiKey:        return "key.fill"
        case .oauthToken:    return "person.badge.key.fill"
        case .sessionCookie: return "globe"
        case .bearerToken:   return "shield.fill"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Usage meters section
// ═══════════════════════════════════════════════════════════════════

struct UsageMetersSectionView: View {
    let statuses: [ProviderCredentialStatus]
    let compact: Bool

    @Environment(\.swooshTheme) var theme

    var body: some View {
        if statuses.isEmpty {
            Text("No usage data available")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
        } else {
            VStack(spacing: compact ? 4 : 8) {
                ForEach(statuses) { status in
                    UsageMeterRow(status: status, compact: compact)
                }
            }
        }
    }
}

struct UsageMeterRow: View {
    let status: ProviderCredentialStatus
    let compact: Bool

    @Environment(\.swooshTheme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(status.displayName)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(status.statusMessage ?? "Active")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.surface.opacity(0.4))
                        .frame(height: compact ? 3 : 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [theme.accent, theme.secondaryAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (status.isHealthy ? 1.0 : 0.15), height: compact ? 3 : 4)
                }
            }
            .frame(height: compact ? 3 : 4)
        }
        .padding(.vertical, 2)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Quick actions section
// ═══════════════════════════════════════════════════════════════════

struct QuickActionsSectionView: View {
    let compact: Bool

    @Environment(\.swooshTheme) var theme

    private let actions: [(icon: String, label: String, key: String)] = [
        ("bubble.left.fill", "Chat", "chat"),
        ("arrow.triangle.branch", "Workflow", "workflow"),
        ("magnifyingglass", "Scout", "scout"),
        ("terminal.fill", "Terminal", "terminal"),
    ]

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            ForEach(actions, id: \.key) { action in
                QuickActionButton(
                    icon: action.icon,
                    label: action.label,
                    compact: compact
                )
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let compact: Bool

    @Environment(\.swooshTheme) var theme
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            Image(systemName: icon)
                .font(.system(size: compact ? 14 : 18, weight: .medium))
                .foregroundStyle(isHovered ? theme.accent : theme.textSecondary)

            Text(label)
                .font(.system(size: compact ? 8 : 9, weight: .medium, design: .rounded))
                .foregroundStyle(isHovered ? theme.textPrimary : theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? theme.accent.opacity(0.1) : .clear)
        )
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isHovered)
    }
}
