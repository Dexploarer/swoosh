// Apps/SwooshiOS/SettingsScreen.swift — Sectioned settings hub
//
// Claude-style replacement for SettingsView. Top-level list of icon-tile
// rows, each pushing to a dedicated detail screen (Pairing, Profile,
// Safety, Tool policy, About). The dense pairing Form moves into its own
// pushed page so the root screen reads as a small, glanceable index.

import SwiftUI
import SwooshClient

struct SettingsScreen: View {
    @Environment(ClientSession.self) private var session

    var body: some View {
        List {
            statusSection
            Section("Daemon") {
                NavigationLink {
                    PairingDetailScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "link", tint: .blue),
                        title: "Pairing",
                        detail: pairingDetail
                    )
                }
            }

            Section("Agent") {
                NavigationLink {
                    PermissionProfileDetailScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "person.crop.circle.badge.checkmark", tint: .green),
                        title: "Permission profile",
                        detail: session.runtimeConfig?.permissionProfile ?? "Unconfigured"
                    )
                }
                NavigationLink {
                    SafetyFlagsDetailScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "checkerboard.shield", tint: .orange),
                        title: "Safety flags",
                        detail: safetyDetail
                    )
                }
                NavigationLink {
                    ToolPolicyDetailScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "wrench.and.screwdriver", tint: .purple),
                        title: "Tool policy",
                        detail: toolPolicyDetail
                    )
                }
            }

            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "info.circle", tint: .gray),
                        title: "About Swoosh"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                IconTile(systemName: statusSymbol, tint: statusTint, size: 40, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.body.weight(.semibold))
                    if let host = session.host {
                        Text(host.host ?? host.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Tap Pairing to connect")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Status helpers

    private var statusSymbol: String {
        switch session.lastHealth {
        case .ok:          "checkmark"
        case .unreachable: "exclamationmark"
        case .unknown:     "questionmark"
        }
    }

    private var statusTint: Color {
        switch session.lastHealth {
        case .ok:          .green
        case .unreachable: .red
        case .unknown:     .gray
        }
    }

    private var statusTitle: String {
        switch session.lastHealth {
        case .ok:          "Daemon reachable"
        case .unreachable: "Daemon unreachable"
        case .unknown:     "Not paired"
        }
    }

    private var pairingDetail: String {
        if let host = session.host {
            return session.lastHealth == .ok ? "Connected · \(host.host ?? host.absoluteString)" : "Saved, currently unreachable"
        }
        return "Not paired"
    }

    private var safetyDetail: String {
        guard let flags = session.runtimeConfig?.safetyFlags else { return "Unknown" }
        let enabled = flags.filter(\.enabled).count
        return "\(enabled) of \(flags.count) enabled"
    }

    private var toolPolicyDetail: String {
        guard let policy = session.runtimeConfig?.toolPolicy else { return "Unknown" }
        return policy.allowModelToolCalls ? "Tool calls on · max \(policy.maxToolCallsPerTurn)" : "Tool calls disabled"
    }
}

// MARK: - Pairing detail

struct PairingDetailScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var hostText: String = ""
    @State private var tokenText: String = ""
    @State private var saveError: String?
    @State private var isProbing: Bool = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Daemon", value: statusLabel)
                if let host = session.host {
                    LabeledContent("Host", value: host.absoluteString)
                }
                if let status = session.agentStatus {
                    LabeledContent("Provider", value: status.provider ?? "Not configured")
                    LabeledContent("Model", value: status.model ?? "Unavailable")
                }
                if let config = session.runtimeConfig {
                    LabeledContent("Profile", value: config.permissionProfile ?? "Unconfigured")
                    LabeledContent("Mode", value: config.setupMode ?? "Unknown")
                }
            } header: {
                Text("Current pairing")
            }

            Section("Pair with swooshd") {
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
                    Label(saveError, systemImage: "exclamationmark.triangle")
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
                Text("On your Mac, run `cd /Users/home/swoosh && SWOOSH_HOST=0.0.0.0 swift run swooshd`, then read `~/.swoosh/api_token`. Paste that here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hostText.isEmpty, let host = session.host {
                hostText = host.absoluteString
            }
        }
    }

    private var statusLabel: String {
        switch session.lastHealth {
        case .ok:          "Reachable"
        case .unreachable: "Unreachable"
        case .unknown:     "Not paired"
        }
    }

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
            saveError = "Couldn't reach \(url.host ?? "host"). Check that swooshd is running and reachable from this phone."
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
}

// MARK: - Profile / safety / tool policy

struct PermissionProfileDetailScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var selected: String = ""
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("Profile", selection: $selected) {
                    ForEach(ProfileOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Active profile")
            } footer: {
                Text("Trader allows mainnet write with human approval. Autonomous is the broadest unattended policy. Restart swooshd after saving.")
            }

            Section {
                Button(saving ? "Saving…" : "Save profile") {
                    Task { await save() }
                }
                .disabled(selected.isEmpty || saving)
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green).font(.footnote)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Permission profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selected = session.runtimeConfig?.permissionProfile ?? "" }
    }

    private func save() async {
        guard let client = session.client(), !selected.isEmpty else { return }
        saving = true
        message = nil
        error = nil
        defer { saving = false }
        do {
            let response = try await client.updateRuntimeProfile(selected)
            message = response.message
            await session.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum ProfileOption: String, CaseIterable, Identifiable {
    case safe, developer, automation, power, trader, autonomous, custom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct SafetyFlagsDetailScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var drafts: [String: Bool] = [:]
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        List {
            if let flags = session.runtimeConfig?.safetyFlags, !flags.isEmpty {
                Section {
                    ForEach(flags) { flag in
                        Toggle(isOn: binding(for: flag)) {
                            Text(flag.label)
                        }
                    }
                } footer: {
                    Text("These gates are configuration only — live tool execution applies them after the next swooshd restart.")
                }

                Section {
                    Button(saving ? "Saving…" : "Save safety flags") {
                        Task { await save(flags: flags) }
                    }
                    .disabled(saving)
                }
            } else {
                Text("No safety flags reported by the daemon.")
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green).font(.footnote)
                }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Safety flags")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { syncDrafts() }
        .onChange(of: session.runtimeConfig) { syncDrafts() }
    }

    private func binding(for flag: RuntimeFlagSummary) -> Binding<Bool> {
        Binding(
            get: { drafts[flag.id] ?? flag.enabled },
            set: { drafts[flag.id] = $0 }
        )
    }

    private func syncDrafts() {
        guard let flags = session.runtimeConfig?.safetyFlags else { return }
        drafts = Dictionary(uniqueKeysWithValues: flags.map { ($0.id, $0.enabled) })
    }

    private func save(flags: [RuntimeFlagSummary]) async {
        guard let client = session.client() else { return }
        saving = true
        message = nil
        error = nil
        defer { saving = false }
        let updates = flags.map { RuntimeFlagUpdate(id: $0.id, enabled: drafts[$0.id] ?? $0.enabled) }
        do {
            let response = try await client.updateRuntimeFlags(updates)
            message = response.message
            await session.refresh()
            syncDrafts()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ToolPolicyDetailScreen: View {
    @Environment(ClientSession.self) private var session

    var body: some View {
        List {
            if let policy = session.runtimeConfig?.toolPolicy {
                Section("Tool calls") {
                    policyRow(
                        tile: IconTile(systemName: "wrench.and.screwdriver.fill", tint: .purple),
                        title: "Tool calls",
                        value: policy.allowModelToolCalls ? "Enabled" : "Disabled"
                    )
                    policyRow(
                        tile: IconTile(systemName: "number", tint: .blue),
                        title: "Max calls per turn",
                        value: "\(policy.maxToolCallsPerTurn)"
                    )
                    policyRow(
                        tile: IconTile(systemName: "link", tint: .teal),
                        title: "Chain depth",
                        value: "\(policy.maxToolChainDepth)"
                    )
                }
                Section("Risk gates") {
                    policyRow(
                        tile: IconTile(systemName: "exclamationmark.octagon.fill", tint: .red),
                        title: "Critical tools",
                        value: policy.allowCriticalToolsFromModel ? "Model allowed" : "Blocked"
                    )
                    policyRow(
                        tile: IconTile(systemName: "person.fill", tint: .orange),
                        title: "Human-only tools",
                        value: policy.allowHumanOnlyFromModel ? "Model allowed" : "Human only"
                    )
                    policyRow(
                        tile: IconTile(systemName: "checkmark.shield.fill", tint: .green),
                        title: "Medium-risk approval",
                        value: policy.requireApprovalForMediumRiskAndAbove ? "Required" : "Optional"
                    )
                }
            } else {
                Text("Tool policy not loaded from daemon.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tool policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policyRow(tile: IconTile, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            tile
            Text(title)
            Spacer(minLength: 0)
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    IconTile(systemName: "sparkles", tint: .accentColor, size: 44, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Swoosh").font(.title3.weight(.semibold))
                        Text("Thin client to swooshd")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Architecture") {
                IconRow(
                    tile: IconTile(systemName: "macmini.fill", tint: .blue),
                    title: "Kernel on Mac",
                    detail: "Agent + tools run in swooshd"
                )
                IconRow(
                    tile: IconTile(systemName: "iphone", tint: .green),
                    title: "iPhone client",
                    detail: "Chat, wallet, settings, connections"
                )
                IconRow(
                    tile: IconTile(systemName: "lock.shield.fill", tint: .orange),
                    title: "Local wallet keys",
                    detail: "Sealed in iOS Keychain, Face ID-gated"
                )
            }
            Section {
                Text("Wallet RPCs call public mainnet endpoints directly from this phone — no daemon round-trip for balances.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
