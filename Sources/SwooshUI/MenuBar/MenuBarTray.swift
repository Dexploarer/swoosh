// SwooshUI/MenuBar/MenuBarTray.swift — 0.1A Swoosh-native menu-bar tray
//
// The menu-bar popover for the macOS app. Owns a neon tab bar and switches
// between Detour's tray surfaces: Chat (the agent shell), Cloud (providers +
// cloud agents), Wallet, Calendar, and Usage. Usage is the CodexBar quota
// panel, injected by the host as a `@ViewBuilder` so this module never
// imports CodexBar. Pure-black canvas, cyan tab-bar accent (one accent per
// surface). Replaces CodexBar's two-tab TrayTabView as the app's tray.

#if os(macOS)

import SwiftUI
import AppKit
import SwooshGenerativeUI

public struct MenuBarTray<Usage: View>: View {
    @Bindable var shell: AgentShellModel
    private let usage: Usage

    public init(shell: AgentShellModel, @ViewBuilder usage: () -> Usage) {
        self.shell = shell
        self.usage = usage()
    }

    enum TrayPanel: String, CaseIterable, Identifiable {
        case chat, cloud, wallet, calendar, usage
        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat: return "Chat"
            case .cloud: return "Cloud"
            case .wallet: return "Wallet"
            case .calendar: return "Calendar"
            case .usage: return "Usage"
            }
        }

        var icon: String {
            switch self {
            case .chat: return "bubble.left.fill"
            case .cloud: return "cloud.fill"
            case .wallet: return "banknote.fill"
            case .calendar: return "calendar"
            case .usage: return "chart.bar.fill"
            }
        }
    }

    @State private var selected: TrayPanel = .chat

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            TrayHairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 400, height: 540)
        .background(SwooshNeonTokens.Canvas.bg)
        .environment(\.colorScheme, .dark)
        // MenuBarExtra(.window) popovers don't become key on open, so a
        // TextField inside can't take keyboard focus — the chat field then
        // silently ignores typing/Return. Activating the app makes the
        // popover focusable.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .chat: AgentShellView(shell: shell, mode: .tray)
        case .cloud: CloudTrayPanel()
        case .wallet: WalletTrayPanel()
        case .calendar: CalendarTrayPanel()
        case .usage: usage
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(TrayPanel.allCases) { panel in
                tabButton(panel)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }

    private func tabButton(_ panel: TrayPanel) -> some View {
        let isSelected = selected == panel
        let accent = NeonAccent.cyan.color
        return Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                selected = panel
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: panel.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(panel.title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isSelected ? accent : SwooshNeonTokens.Canvas.text3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(SwooshNeonTokens.Line.dim) : .clear,
                                  lineWidth: SwooshNeonTokens.Line.width)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#endif
