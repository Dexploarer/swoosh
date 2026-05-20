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

enum DrawerDestination: Hashable {
    case wallet
    case connections
    case settings
}

struct RootView: View {
    @Environment(ClientSession.self) private var session
    @State private var wallet = WalletSession()
    @State private var drawerOpen: Bool = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ChatScreen(
                onOpenDrawer: { withAnimation(.easeOut(duration: 0.22)) { drawerOpen = true } }
            )
            .navigationDestination(for: DrawerDestination.self) { destination in
                switch destination {
                case .wallet:      WalletScreen().environment(wallet)
                case .connections: ControlCenterView().navigationTitle("Connections")
                case .settings:    SettingsView().navigationTitle("Settings")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
        .task { await wallet.reload() }
    }
}
