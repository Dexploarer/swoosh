// Apps/SwooshiOS/ErrorRow.swift — Shared error row with a Retry affordance
//
// Every daemon call that can fail surfaces its error through one of these
// instead of static red text. The visual (orange/red exclamation `Label`)
// matches what the screens already used; the addition is a trailing
// **Retry** button that re-runs the failed operation.

import SwiftUI

/// An inline error `Label` with a trailing **Retry** button. Use inside a
/// `List` section or a `Form` section — the retry closure re-runs the
/// operation that failed.
struct ErrorRow: View {
    let message: String
    /// Tint for the icon/text. Defaults to `.red`; pass `.orange` for
    /// recoverable / soft warnings.
    var tint: Color = .red
    /// Re-run the failed operation. When `nil`, no Retry button shows.
    var retry: (() async -> Void)?

    @State private var retrying = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(tint)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button {
                    Task {
                        retrying = true
                        await retry()
                        retrying = false
                    }
                } label: {
                    if retrying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Retry").font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(retrying)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityHint(retry == nil ? "" : "Double tap to retry")
    }
}

/// A compact, free-standing error banner for screens that show errors
/// outside of a `List` (e.g. the chat composer area). Carries the same
/// Retry affordance.
struct ErrorBanner: View {
    let message: String
    var retry: (() async -> Void)?

    @State private var retrying = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button {
                    Task {
                        retrying = true
                        await retry()
                        retrying = false
                    }
                } label: {
                    if retrying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Retry").font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(retrying)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.12))
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
        .accessibilityHint(retry == nil ? "" : "Double tap to retry")
    }
}
