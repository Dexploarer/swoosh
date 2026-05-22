// Apps/SwooshiOS/RootView.swift — Claude-style home: chat as the only primary
// surface, drawer for everything else.
//
// The previous build used a four-tab TabView (Chat / Control / Wallet /
// Settings). That spread attention across surfaces nobody used at once.
// We now mirror Claude's mobile shell: a full-bleed chat with a top bar
// (hamburger ↔ side drawer, model picker placeholder, new-chat button),
// and every adjacent surface (Wallet, Connections, Settings) lives inside
// the drawer as a pushed destination.

import SwiftUI
import SwooshUI

enum DrawerDestination: Hashable {
    case workspace
    case wallet
    case connections
    case settings
    case mcpServers
}

struct RootView: View {
    @Environment(ClientSession.self) private var session
    @State private var wallet = WalletSession()
    /// One AgentShellModel for the whole iOS app — hoisted above
    /// NavigationStack so every destination (Workspace, etc.) inherits
    /// it via the environment. Otherwise pushed views fatalError on
    /// `@Environment(AgentShellModel.self)`.
    @State private var shell = AgentShellModel()
    @State private var drawerOpen: Bool = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            AgentRoot(
                shell: shell,
                onOpenDrawer: { withAnimation(.easeOut(duration: 0.22)) { drawerOpen = true } },
                onNavigate: { destination in path.append(destination) }
            )
            .navigationDestination(for: DrawerDestination.self) { destination in
                switch destination {
                case .workspace:   WorkspaceScreen()
                case .wallet:      WalletScreen().environment(wallet)
                case .connections: ConnectionsScreen()
                case .settings:    SettingsScreen()
                case .mcpServers:  MCPServersScreen()
                }
            }
        }
        .overlay(alignment: .leading) {
            if drawerOpen {
                SideDrawer(
                    isOpen: $drawerOpen,
                    onSelect: { destination in
                        withAnimation(.easeOut(duration: 0.22)) { drawerOpen = false }
                        path.append(destination)
                    }
                )
                .transition(.move(edge: .leading))
                .zIndex(1)
            }
        }
        .environment(wallet)
        .environment(shell)
        .task { await wallet.reload() }
    }
}
