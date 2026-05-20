// Apps/SwooshiOS/SettingsView.swift — Pairing form + daemon health probe
//
// Single screen with two fields (host URL + bearer token), a Save button
// that tries the `/health` endpoint, and an "Unpair" button. The token is
// pasted, not generated here — the user copies it from swooshd's startup
// log on their Mac. This is the same trust model as classic SSH key-paste:
// crude, but explicit and auditable.

import SwiftUI
import SwooshClient

struct SettingsView: View {
    @Environment(ClientSession.self) private var session
    @State private var hostText: String = ""
    @State private var tokenText: String = ""
    @State private var saveError: String?
    @State private var isProbing: Bool = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Daemon") {
                    statusBadge
                }
                if let host = session.host {
                    LabeledContent("Host", value: host.absoluteString)
                        .foregroundStyle(.secondary)
                }
                if let status = session.agentStatus {
                    LabeledContent("Provider", value: status.provider ?? "Not configured")
                        .foregroundStyle(.secondary)
                    LabeledContent("Model", value: status.model ?? "Unavailable")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pairing status")
            } footer: {
                Text("The agent runs on your Mac. This phone is a thin client to it.")
            }

            Section("Mac swooshd") {
                TextField("http://mac.local:8787", text: $hostText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Bearer token", text: $tokenText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Pair with daemon")
                        Spacer()
                        if isProbing { ProgressView() }
                    }
                }
                .disabled(hostText.isEmpty || tokenText.isEmpty || isProbing)

                if session.isPaired {
                    Button("Unpair", role: .destructive) {
                        Task { await session.unpair() }
                    }
                }
            }

            Section("Where do I find the token?") {
                Text("Run `swooshd` on your Mac. It prints a line like `API token: <token>` once during startup. Paste that here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if hostText.isEmpty, let host = session.host {
                hostText = host.absoluteString
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.lastHealth {
        case .ok:
            Label("Reachable", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unreachable:
            Label("Unreachable", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .unknown:
            Label("Not paired", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Save flow

    private func save() async {
        saveError = nil
        guard let url = URL(string: hostText), url.scheme != nil else {
            saveError = "Host URL must include scheme (http:// or https://)."
            return
        }
        isProbing = true
        defer { isProbing = false }

        // Probe /health with the supplied URL before persisting, so a bad
        // pairing fails fast instead of greeting the user with "Network
        // error" the next time they open Chat.
        let probe = SwooshAPIClient(baseURL: url, token: tokenText)
        let healthy = await probe.health()
        if !healthy {
            saveError = "Couldn't reach \(url.host ?? "host") at /health. Check that swooshd is running and reachable from this phone."
            return
        }

        do {
            try await session.pair(host: url, token: tokenText)
            tokenText = ""
        } catch {
            saveError = error.localizedDescription
        }
    }
}
