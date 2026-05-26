// DetourAgentPresenceView.swift — optional agent presence fallback (0.5A)

import SwiftUI

struct DetourAgentPresenceView: View {
    let name: String
    let verifiedCount: Int
    let attentionCount: Int

    var body: some View {
        #if canImport(RealityKit)
        if #available(macOS 26.0, iOS 26.0, visionOS 26.0, *) {
            realityPresence
        } else {
            fallbackPresence
        }
        #else
        fallbackPresence
        #endif
    }

    private var fallbackPresence: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(attentionCount == 0 ? Color.green : Color.orange)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "sparkles").foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? OnboardingStore.defaultAgentName : name)
                    .font(.headline)
                Text("\(verifiedCount) ready, \(attentionCount) need attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if canImport(RealityKit)
    @available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
    private var realityPresence: some View {
        fallbackPresence
    }
    #endif
}
