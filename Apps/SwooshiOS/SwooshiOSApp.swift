// SwooshiOSApp.swift — rebuilt Detour iPhone and iPad entry point (0.5A)

import SwiftUI

@main
struct SwooshiOSApp: App {
    @StateObject private var store = DetouriOSOnboardingStore()
    @StateObject private var speech = DetouriOSSpeechService()

    var body: some Scene {
        WindowGroup {
            DetouriOSOnboardingView(store: store, speech: speech)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    store.handlePairingURL(url)
                    Task {
                        await store.refreshPairedMacReachability()
                    }
                }
        }
    }
}
