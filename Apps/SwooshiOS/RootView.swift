// Apps/SwooshiOS/RootView.swift — Tab shell + first-run pairing gate
//
// Two surfaces while the slice is small: Chat and Settings. Pairing state
// lives in ClientSession, and Chat owns the unpaired pairing prompt.

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
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
