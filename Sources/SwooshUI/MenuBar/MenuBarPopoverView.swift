// SwooshUI/MenuBar/MenuBarPopoverView.swift — The main menu bar popover
//
// Renders sections based on the active configuration.
// Each section is a collapsible card. Supports all card styles.

import SwiftUI
import SwooshGenerativeUI
#if os(macOS)
import AppKit
#endif

public struct MenuBarPopoverView: View {
    @Bindable var manager: MenuBarManager
    @Environment(\.swooshTheme) var theme
    @Environment(AgentShellModel.self) private var shell
    @Environment(\.openWindow) private var openWindow

    public init(manager: MenuBarManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            Divider().opacity(0.18)
            quickActions
            Divider().opacity(0.18)
            recentSection
            Divider().opacity(0.18)
            footerActions
        }
        .frame(width: 320)
        .background(SwooshNeonTokens.Canvas.bg)
        .task(id: "popover-health-probe") {
            await refreshDaemonHealth()
        }
    }

    private func refreshDaemonHealth() async {
        let healthy = await SwooshDaemonClient.health()
        await MainActor.run {
            switch shell.syncState {
            case .queued: break
            default:
                shell.syncState = healthy ? .online : .offline
            }
        }
    }

    // MARK: - Status header

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(theme.accent)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Detour")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 0)
                    connectionPill
                }
                Text(activeProviderLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var connectionPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)
            Text(shell.syncState.label.capitalized)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.85))
                .textCase(nil)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(connectionColor.opacity(0.14))
        )
        .overlay(
            Capsule().strokeBorder(connectionColor.opacity(0.32), lineWidth: 0.5)
        )
    }

    private var connectionColor: Color {
        switch shell.syncState {
        case .online: return .green
        case .offline: return .orange
        case .queued: return .yellow
        }
    }

    private var activeProviderLabel: String {
        if let active = manager.providerStatuses.first(where: { $0.isHealthy }) {
            return active.displayName
        }
        if !manager.providerStatuses.isEmpty {
            return "No provider signed in"
        }
        return "Loading providers…"
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(spacing: 1) {
            TrayActionRow(
                icon: "macwindow",
                title: "Open Dashboard",
                accent: theme.accent,
                shortcut: "⌘1"
            ) {
                openWindow(id: "dashboard")
                dismissPopover()
            }

            TrayActionRow(
                icon: "mic.circle",
                title: "Voice Mode",
                accent: .cyan,
                shortcut: "⇧⌥␣"
            ) {
                NotificationCenter.default.post(
                    name: Notification.Name("ai.swoosh.toggleVoiceMode"),
                    object: nil
                )
                dismissPopover()
            }

            if !hasSignedInLLM {
                TrayActionRow(
                    icon: "person.badge.key.fill",
                    title: "Sign in with ChatGPT",
                    accent: .green
                ) {
                    Task { await startCodexAuth() }
                }
            }

            TrayActionRow(
                icon: "arrow.clockwise",
                title: "Refresh Providers",
                accent: theme.textPrimary.opacity(0.7),
                trailing: manager.isRefreshing ? AnyView(ProgressView().controlSize(.small)) : nil
            ) {
                Task { await manager.refreshCredentials() }
            }
        }
        .padding(.vertical, 4)
    }

    private var hasSignedInLLM: Bool {
        manager.providerStatuses.contains { $0.isHealthy }
    }

    private func startCodexAuth() async {
        openWindow(id: "dashboard")
        NotificationCenter.default.post(name: .swooshOpenDashboardTab, object: "providers")
        dismissPopover()
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.textPrimary.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.top, 8)

            let userMessages = shell.messages.filter { $0.role == .user }.suffix(3)
            if userMessages.isEmpty {
                Text("No recent chats")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.55))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(userMessages), id: \.id) { msg in
                    RecentChatRow(text: msg.text, timestamp: msg.timestamp) {
                        openWindow(id: "dashboard")
                        NotificationCenter.default.post(name: .swooshOpenDashboardTab, object: "chat")
                        dismissPopover()
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: 4) {
            Button {
                openWindow(id: "dashboard")
                NotificationCenter.default.post(name: .swooshOpenDashboardTab, object: "settings")
                dismissPopover()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.78))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)

            Spacer()

            if !manager.providerStatuses.isEmpty {
                Text("\(manager.providerStatuses.count) providers")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 6)
            }

            #if os(macOS)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.78))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .help("Quit Detour")
            #endif
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func dismissPopover() {
        #if os(macOS)
        NSApp.deactivate()
        #endif
    }
}

public extension Notification.Name {
    static let swooshOpenDashboardTab = Notification.Name("swoosh.openDashboardTab")
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Action row
// ═══════════════════════════════════════════════════════════════════

private struct TrayActionRow: View {
    @Environment(\.swooshTheme) var theme
    let icon: String
    let title: String
    var accent: Color = .accentColor
    var shortcut: String? = nil
    var trailing: AnyView? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                if let trailing { trailing }

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textPrimary.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                Rectangle()
                    .fill(hovering ? theme.textPrimary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentChatRow: View {
    @Environment(\.swooshTheme) var theme
    let text: String
    let timestamp: Date
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.5))
                    .frame(width: 22)

                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text(timestamp, style: .relative)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                Rectangle()
                    .fill(hovering ? theme.textPrimary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
