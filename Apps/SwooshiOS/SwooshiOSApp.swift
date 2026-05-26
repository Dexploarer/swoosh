// SwooshiOSApp.swift — rebuilt Detour iPhone and iPad entry point (0.5A)

import SwiftUI

@main
struct SwooshiOSApp: App {
    @StateObject private var store = DetouriOSOnboardingStore()
    @StateObject private var speech = DetouriOSSpeechService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DetouriOSOnboardingView(store: store, speech: speech)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    Task {
                        await store.handlePairingURL(url)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await store.reconnectPairedMac()
                    }
                }
        }
    }
}
