// SwooshUI/DashboardPanes/ProvidersConfigPane.swift — Provider configuration dashboard pane — 0.9U

#if os(macOS)

import SwiftUI
import SwooshClient
import SwooshConfig
import SwooshCore
import SwooshGenerativeUI
import SwooshModels
import SwooshTools

struct ProvidersConfigPane: View {
    @Environment(\.swooshTheme) var theme
    @State private var snapshot: ProvidersResponse?
    @State private var codexAuth: CodexAuthStatus?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        DashboardPane(
            title: "Providers",
            icon: "cloud",
            subtitle: "Switch between cloud subscriptions, local models, and on-device inference"
        ) {
            if let error {
                OfflineBanner(reason: error)
            }

            HStack(spacing: 10) {
                StatBadge(
                    value: "\(snapshot?.providers.count ?? 0)",
                    label: "Configured",
                    tint: .cyan
                )
                StatBadge(
                    value: activeName,
                    label: "Active",
                    tint: .green
                )
                StatBadge(
                    value: "\(healthyCount)",
                    label: "Signed in",
                    tint: .blue
                )
            }

            ForEach(orderedProviders, id: \.id) { provider in
                ProviderConfigCard(
                    provider: provider,
                    isActive: snapshot?.activeProviderID == provider.id,
                    codexAuth: provider.id == "codex" ? codexAuth : nil,
                    onActivate: { await activate(provider.id) },
                    onSaveAPIKey: { key in await saveKey(provider.id, key: key) },
                    onStartCodexLogin: { await startCodex() },
                    onCancelCodexLogin: { await cancelCodex() },
                    onRefresh: { await load() }
                )
            }
        }
        .task { await load() }
    }

    private var activeName: String {
        guard let snap = snapshot,
              let active = snap.activeProviderID,
              let row = snap.providers.first(where: { $0.id == active }) else { return "—" }
        return row.name
    }

    private var healthyCount: Int {
        snapshot?.providers.filter { $0.configured }.count ?? 0
    }

    private var orderedProviders: [ProviderSummary] {
        guard let snap = snapshot else { return [] }
        return DashboardProviderOrdering.orderedProviders(snap.providers)
    }

    private func load() async {
        guard let client = makeClient() else {
            error = "Daemon offline — pair the iPhone or restart swooshd."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await client.providers()
            snapshot = resp
            if let codex = try? await client.codexAuthStatus() {
                codexAuth = codex
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func activate(_ id: String) async {
        guard let client = makeClient() else { return }
        _ = try? await client.selectProvider(providerID: id)
        await load()
    }

    private func saveKey(_ id: String, key: String) async {
        guard let client = makeClient() else { return }
        _ = try? await client.saveProviderKey(providerID: id, apiKey: key)
        await load()
    }

    private func startCodex() async {
        guard let client = makeClient() else { return }
        codexAuth = try? await client.startCodexAuth()
        // The daemon polls codex login internally; the user finishes
        // in their browser. We poll status until terminal.
        while let st = codexAuth, st.state == .pending {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            codexAuth = try? await client.codexAuthStatus()
        }
        await load()
    }

    private func cancelCodex() async {
        guard let client = makeClient() else { return }
        codexAuth = try? await client.cancelCodexAuth()
    }
}

#endif
