// Apps/SwooshiOS/SettingsView.swift — Pairing form + authenticated daemon probe
//
// Single screen with two fields (host URL + bearer token), a Save button
// that tries an authenticated `/api/agent/status` request, and an "Unpair"
// button. The token is pasted, not generated here.

import SwiftUI
import SwooshClient

struct SettingsView: View {
    @Environment(ClientSession.self) private var session
    @State private var hostText: String = ""
    @State private var tokenText: String = ""
    @State private var saveError: String?
    @State private var isProbing: Bool = false
    @State private var selectedProfile: String = ""
    @State private var safetyFlagDrafts: [String: Bool] = [:]
    @State private var isSavingRuntime = false
    @State private var runtimeMessage: String?

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
                if let config = session.runtimeConfig {
                    LabeledContent("Profile", value: config.permissionProfile ?? "Unconfigured")
                        .foregroundStyle(.secondary)
                    LabeledContent("Mode", value: config.setupMode ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pairing status")
            } footer: {
                Text("The agent runs on your Mac. This phone is a thin client to it.")
            }

            if session.runtimeConfig != nil {
                Section {
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(RuntimeProfileOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    Button {
                        Task { await saveRuntimeProfile() }
                    } label: {
                        HStack {
                            Text("Save profile")
                            Spacer()
                            if isSavingRuntime { ProgressView() }
                        }
                    }
                    .disabled(selectedProfile.isEmpty || isSavingRuntime)
                } header: {
                    Text("Permission profile")
                } footer: {
                    Text("Trader enables mainnet write permissions with human approval. Autonomous enables the broadest unattended policy. Restart swooshd after saving.")
                }
            }

            if let policy = session.runtimeConfig?.toolPolicy {
                Section("Tool policy") {
                    LabeledContent("Tool calls", value: policy.allowModelToolCalls ? "Enabled" : "Disabled")
                    LabeledContent("Max calls", value: "\(policy.maxToolCallsPerTurn)")
                    LabeledContent("Chain depth", value: "\(policy.maxToolChainDepth)")
                    LabeledContent("Critical tools", value: policy.allowCriticalToolsFromModel ? "Model allowed" : "Blocked")
                    LabeledContent("Human-only tools", value: policy.allowHumanOnlyFromModel ? "Model allowed" : "Human only")
                    LabeledContent("Medium-risk approval", value: policy.requireApprovalForMediumRiskAndAbove ? "Required" : "Optional")
                }
            }

            if let flags = session.runtimeConfig?.safetyFlags, !flags.isEmpty {
                Section {
                    ForEach(flags) { flag in
                        Toggle(isOn: flagBinding(for: flag)) {
                            Text(flag.label)
                        }
                    }
                    Button {
                        Task { await saveRuntimeFlags(flags) }
                    } label: {
                        HStack {
                            Text("Save safety flags")
                            Spacer()
                            if isSavingRuntime { ProgressView() }
                        }
                    }
                    .disabled(isSavingRuntime)
                } header: {
                    Text("Safety flags")
                } footer: {
                    Text("These gates are optional configuration, but live tool execution uses them only after the Mac daemon restarts.")
                }
            }

            if let runtimeMessage {
                Section {
                    Label(runtimeMessage, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
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
                Text("From this checkout, run `cd /Users/home/swoosh && SWOOSH_HOST=0.0.0.0 swift run swooshd`, then read `~/.swoosh/api_token`. Paste that token here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if hostText.isEmpty, let host = session.host {
                hostText = host.absoluteString
            }
            syncRuntimeDrafts()
        }
        .onChange(of: session.runtimeConfig) {
            syncRuntimeDrafts()
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

        let probe = SwooshAPIClient(baseURL: url, token: tokenText)
        let healthy = await probe.health()
        if !healthy {
            saveError = "Couldn't reach \(url.host ?? "host") at /health. Check that swooshd is running and reachable from this phone."
            return
        }
        do {
            _ = try await probe.agentStatus()
        } catch {
            saveError = "Reached swooshd, but the bearer token was rejected. Check ~/.swoosh/api_token on your Mac."
            return
        }

        do {
            try await session.pair(host: url, token: tokenText)
            tokenText = ""
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func syncRuntimeDrafts() {
        selectedProfile = session.runtimeConfig?.permissionProfile ?? selectedProfile
        if let flags = session.runtimeConfig?.safetyFlags {
            safetyFlagDrafts = Dictionary(uniqueKeysWithValues: flags.map { ($0.id, $0.enabled) })
        }
    }

    private func flagBinding(for flag: RuntimeFlagSummary) -> Binding<Bool> {
        Binding(
            get: { safetyFlagDrafts[flag.id] ?? flag.enabled },
            set: { safetyFlagDrafts[flag.id] = $0 }
        )
    }

    private func saveRuntimeFlags(_ flags: [RuntimeFlagSummary]) async {
        guard let client = session.client() else { return }
        isSavingRuntime = true
        runtimeMessage = nil
        saveError = nil
        defer { isSavingRuntime = false }
        let updates = flags.map { RuntimeFlagUpdate(id: $0.id, enabled: safetyFlagDrafts[$0.id] ?? $0.enabled) }
        do {
            let response = try await client.updateRuntimeFlags(updates)
            runtimeMessage = response.message
            await session.refresh()
            syncRuntimeDrafts()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveRuntimeProfile() async {
        guard let client = session.client(), !selectedProfile.isEmpty else { return }
        isSavingRuntime = true
        runtimeMessage = nil
        saveError = nil
        defer { isSavingRuntime = false }
        do {
            let response = try await client.updateRuntimeProfile(selectedProfile)
            runtimeMessage = response.message
            await session.refresh()
            syncRuntimeDrafts()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private enum RuntimeProfileOption: String, CaseIterable, Identifiable {
    case safe
    case developer
    case automation
    case power
    case trader
    case autonomous
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: "Safe"
        case .developer: "Developer"
        case .automation: "Automation"
        case .power: "Power"
        case .trader: "Trader"
        case .autonomous: "Autonomous"
        case .custom: "Custom"
        }
    }
}
