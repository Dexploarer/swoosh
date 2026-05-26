// DetourTrayMenuView.swift — menu-bar setup status surface (0.5A)

import AppKit
import SwiftUI

struct DetourTrayMenuView: View {
    @ObservedObject var store: OnboardingStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Divider()
                    capabilitySummary
                }
                .padding(18)
            }

            Divider()
            actions
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(width: 420, height: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.agentName.isEmpty ? OnboardingStore.defaultAgentName : store.agentName)
                .font(.title2.weight(.semibold))
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var capabilitySummary: some View {
        let snapshot = store.setupInsightSnapshot
        return VStack(alignment: .leading, spacing: 10) {
            Text("Setup")
                .font(.headline)
            Text(snapshot.summary.plainText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            DetourAgentPresenceView(
                name: store.agentName,
                verifiedCount: snapshot.summary.verified,
                attentionCount: snapshot.summary.needsAttention
            )
            DetourSetupInsightChartPanel(summary: snapshot.summary)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            DetourSetupMapView(sections: snapshot.sections)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Open Detour") {
                DetourWindowActions.showMainWindow()
            }
            .buttonStyle(.borderedProminent)

            Button("Review setup") {
                store.reopenPersonalizationSetup()
                DetourWindowActions.showMainWindow()
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private var statusText: String {
        switch store.step {
        case .complete:
            "Running from the menu bar."
        case .reviewingPersonalizationScan:
            "Setup review is waiting."
        case .runningPersonalizationScan:
            "Scanning this Mac."
        default:
            "Onboarding is in progress."
        }
    }
}
