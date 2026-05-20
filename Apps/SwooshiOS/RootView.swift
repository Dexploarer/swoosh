// Apps/SwooshiOS/RootView.swift — Tab shell + first-run pairing gate
//
// Chat, daemon control, and pairing settings. Pairing state lives in
// ClientSession, and each surface owns its unpaired prompt.

import SwiftUI

struct RootView: View {
    @Environment(ClientSession.self) private var session

    var body: some View {
        TabView {
            NavigationStack {
                ChatView()
                    .navigationTitle("Swoosh")
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            NavigationStack {
                ControlCenterView()
                    .navigationTitle("Control")
            }
            .tabItem { Label("Control", systemImage: "slider.horizontal.3") }

            NavigationStack {
                WalletView()
                    .navigationTitle("Wallet")
            }
            .tabItem { Label("Wallet", systemImage: "wallet.pass") }

            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
