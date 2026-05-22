// Apps/SwooshiOS/SideDrawer.swift — Claude-style left drawer
//
// Slide-in panel triggered by the hamburger in ChatScreen. Lists the user's
// recent chats (just the active one for now — multi-session lands when the
// daemon's transcript API is split per-thread), and links to the three
// adjacent surfaces (Wallet, Connections, Settings).

import SwiftUI
import SwooshUI

struct SideDrawer: View {
    @Environment(ClientSession.self) private var session
    @Environment(WalletSession.self) private var wallet
    @Environment(AgentShellModel.self) private var shell
    @Binding var isOpen: Bool
    let onSelect: (DrawerDestination) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Scrim — tap to dismiss.
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.22)) { isOpen = false }
                }

            // Drawer panel.
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel("Recent")
                        recentRow
                        Divider().padding(.vertical, 6)
                        sectionLabel("Surfaces")
                        drawerLink(.workspace,   title: "Workspace",   symbol: "square.grid.2x2", caption: nil)
                        drawerLink(.wallet,      title: "Wallet",      symbol: "wallet.pass", caption: walletCaption)
                        drawerLink(.connections, title: "Connections", symbol: "slider.horizontal.3", caption: connectionsCaption)
                        drawerLink(.settings,    title: "Settings",    symbol: "gear",        caption: settingsCaption)
                        Spacer(minLength: 32)
                    }
                    .padding(.vertical, 12)
                }

                footer
            }
            .frame(maxWidth: 320, maxHeight: .infinity, alignment: .leading)
            .background(.thinMaterial)
            // Only extend material under the home indicator. Respecting
            // the top safe area drops the "Detour" dropdown beneath the
            // Dynamic Island so it isn't clipped or hard to tap.
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(alignment: .center) {
            Menu {
                Section {
                    Button {
                        shell.clearConversation()
                        withAnimation(.easeOut(duration: 0.22)) { isOpen = false }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    Button {
                        onSelect(.connections)
                    } label: {
                        Label("Connections", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        onSelect(.mcpServers)
                    } label: {
                        Label("MCP Servers", systemImage: "puzzlepiece.extension")
                    }
                }
                Section {
                    Button {
                        onSelect(.settings)
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
                Section {
                    Text("Detour · Built on Swoosh")
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Detour")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Detour menu")
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.22)) { isOpen = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close drawer")
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            statusDot
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    // MARK: - Rows

    private var recentRow: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.22)) { isOpen = false } }) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .frame(width: 22, alignment: .leading)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Current chat")
                        .foregroundStyle(.primary)
                    Text(session.sessionID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func drawerLink(
        _ destination: DrawerDestination,
        title: String,
        symbol: String,
        caption: String?
    ) -> some View {
        Button(action: { onSelect(destination) }) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 22, alignment: .leading)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let caption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    // MARK: - Captions

    private var walletCaption: String {
        let n = wallet.accounts.count
        return n == 0 ? "No accounts" : "\(n) account\(n == 1 ? "" : "s")"
    }

    private var connectionsCaption: String? {
        guard let status = session.agentStatus, let provider = status.provider else {
            return session.isPaired ? "Daemon paired" : nil
        }
        return provider
    }

    private var settingsCaption: String {
        switch session.lastHealth {
        case .ok:          "Daemon reachable"
        case .unreachable: "Daemon unreachable"
        case .unknown:     "Not paired"
        }
    }

    // MARK: - Status

    private var statusDot: some View {
        Circle()
            .frame(width: 8, height: 8)
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch session.lastHealth {
        case .ok:          .green
        case .unreachable: .red
        case .unknown:     .gray
        }
    }

    private var footerText: String {
        if let host = session.host {
            return "swooshd @ \(host.host ?? host.absoluteString)"
        }
        return "Not paired — open Settings to pair"
    }
}
