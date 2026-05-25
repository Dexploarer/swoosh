// DetourOnboardingNativeView.swift — SwiftUI host for native Detour onboarding (0.5A)

import SwiftUI

struct DetourOnboardingNativeView: NSViewRepresentable {
    @ObservedObject var store: OnboardingStore
    @ObservedObject var speech: DetourSpeechService
    let onExit: () -> Void

    func makeNSView(context: Context) -> DetourOnboardingContentView {
        DetourOnboardingContentView(
            frame: .zero,
            store: store,
            speech: speech,
            exit: onExit
        )
    }

    func updateNSView(_ nsView: DetourOnboardingContentView, context: Context) {}
}
