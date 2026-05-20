// Apps/SwooshiOS/SwooshiOSApp.swift — Swoosh iOS app entry point
//
// The iOS app is a thin client to swooshd running on the user's Mac. It
// never embeds the kernel or any subprocess — every chat turn round-trips
// through `POST /api/agent/chat`. Pairing is a one-time step: copy the
// bearer token printed in `swooshd`'s startup log into Settings → Pair.

import SwiftUI
import SwooshClient

@main
struct SwooshiOSApp: App {
    @State private var session = ClientSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.refresh() }
                .onOpenURL { url in
                    Task { await session.pair(url: url) }
                }
        }
    }
}
