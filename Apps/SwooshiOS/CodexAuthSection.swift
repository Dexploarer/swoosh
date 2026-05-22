// Apps/SwooshiOS/CodexAuthSection.swift — "Sign in with ChatGPT" UI
//
// Shown inside `ProviderDetailScreen` when the provider is `codex`. Three
// states: idle (button to start), pending (URL + polling spinner), signed-in
// (green status, sign-out option). The OAuth callback always lands on the
// Mac (where `codex login` runs as a subprocess of swooshd), so when the
// iPhone is the entry point we surface the URL and a "Copy" button so the
// user can finish the OAuth flow on the Mac.

import SwiftUI
import SwooshClient
import UIKit

struct CodexAuthSection: View {
    @Environment(ClientSession.self) private var session
    let configured: Bool

    @State private var status: CodexAuthStatus?
    @State private var working = false
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        Section {
            statusRow
            actionButtons
            if let url = status?.url, status?.state == .pending {
                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Label("Copy sign-in URL", systemImage: "doc.on.doc")
                }
                Text(url)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        } header: {
            Text("ChatGPT sign-in")
        } footer: {
            footerText
        }
        .task { await refresh() }
        .onDisappear { pollTask?.cancel() }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 10) {
            switch status?.state ?? (configured ? .signedIn : .idle) {
            case .signedIn:
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Signed in to ChatGPT").font(.body.weight(.semibold))
            case .pending:
                ProgressView().controlSize(.small)
                Text(status?.message ?? "Sign-in in progress…")
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(status?.message ?? "Sign-in failed").font(.body)
            case .cancelled:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                Text("Sign-in cancelled")
            case .idle:
                Image(systemName: "person.circle").foregroundStyle(.secondary)
                Text(configured ? "Signed in to ChatGPT" : "Not signed in").font(.body)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch status?.state ?? (configured ? .signedIn : .idle) {
        case .pending:
            Button(role: .destructive) {
                Task { await cancel() }
            } label: {
                Label("Cancel sign-in", systemImage: "xmark")
            }
            .disabled(working)
        case .signedIn:
            EmptyView()   // sign-out is a Mac-side concern for now
        case .idle, .failed, .cancelled:
            Button {
                Task { await startAuth() }
            } label: {
                Label(working ? "Starting…" : "Sign in with ChatGPT",
                      systemImage: "person.badge.key.fill")
            }
            .disabled(working)
        }
    }

    @ViewBuilder
    private var footerText: some View {
        switch status?.state ?? .idle {
        case .pending:
            Text("Sign in on the Mac running swooshd. The callback lands on the Mac, then the daemon notices and routes future chats through ChatGPT.")
        case .signedIn:
            Text("Future chat turns route through your ChatGPT Plus / Pro subscription via the local Codex CLI.")
        case .failed:
            Text("Tap Sign in to try again. The codex CLI on the Mac must be installed and reachable.")
        default:
            Text("Uses your ChatGPT Plus / Pro subscription via the local Codex CLI. No API key needed.")
        }
    }

    // MARK: - Networking

    private func refresh() async {
        guard let client = session.client() else { return }
        do {
            let next = try await client.codexAuthStatus()
            self.status = next
            if next.state == .pending { startPolling() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startAuth() async {
        guard let client = session.client() else { return }
        working = true; error = nil
        defer { working = false }
        do {
            let next = try await client.startCodexAuth()
            self.status = next
            if next.state == .pending { startPolling() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cancel() async {
        guard let client = session.client() else { return }
        working = true
        defer { working = false }
        pollTask?.cancel()
        if let next = try? await client.cancelCodexAuth() {
            self.status = next
        }
    }

    /// Poll the status endpoint every 2s while the login is in flight.
    /// Stops automatically when the state changes away from `.pending`.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard let client = session.client() else { return }
                do {
                    let next = try await client.codexAuthStatus()
                    self.status = next
                    if next.state != .pending { break }
                } catch {
                    // Transient failures don't kill the poll loop.
                    continue
                }
            }
        }
    }
}
