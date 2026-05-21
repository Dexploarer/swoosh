// Apps/SwooshiOS/LoadingRow.swift — Shared loading indicator row
//
// A spinner + label used across every screen that loads remote data
// (Chat, Connections, Channels). Replaces the copy-pasted inline
// `HStack { ProgressView(); Text(...) }` blocks so loading states read
// the same everywhere.

import SwiftUI

/// Inline `ProgressView` + secondary label. Drop into a `List` section,
/// a `LazyVStack`, or anywhere a one-line "loading…" affordance is wanted.
struct LoadingRow: View {
    let label: String

    init(_ label: String = "Loading…") {
        self.label = label
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Full-bleed centered loading state for an otherwise-blank screen.
struct LoadingState: View {
    let label: String

    init(_ label: String = "Loading…") {
        self.label = label
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
