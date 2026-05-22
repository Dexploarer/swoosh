// Apps/SwooshiOS/PermissionAndPolicyScreens.swift
// Version: 0.9R
//
// Extracted from SettingsScreen.swift to honor the <350 LOC convention.
// Hosts the Settings detail screens for permission profile, safety
// flags, tool policy, and the About screen.

import SwiftUI
import SwooshClient

// MARK: - Permission profile

struct PermissionProfileDetailScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var selected: String = ""
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

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
                    ErrorRow(message: error) { await save() }
                }
            }
        }
        .navigationTitle("Permission profile")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
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
            withAnimation(.easeOut(duration: 0.22)) { message = response.message }
            successFeedback &+= 1
            await session.refresh()
        } catch {
            withAnimation(.easeOut(duration: 0.22)) { self.error = error.localizedDescription }
            errorFeedback &+= 1
        }
    }
}

private enum ProfileOption: String, CaseIterable, Identifiable {
    case safe, developer, automation, power, trader, autonomous, custom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// MARK: - Safety flags

struct SafetyFlagsDetailScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var drafts: [String: Bool] = [:]
    @State private var saving = false
    @State private var message: String?
    @State private var error: String?
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

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
                    ErrorRow(message: error) {
                        if let flags = session.runtimeConfig?.safetyFlags {
                            await save(flags: flags)
                        }
                    }
                }
            }
        }
        .navigationTitle("Safety flags")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
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
            withAnimation(.easeOut(duration: 0.22)) { message = response.message }
            successFeedback &+= 1
            await session.refresh()
            syncDrafts()
        } catch {
            withAnimation(.easeOut(duration: 0.22)) { self.error = error.localizedDescription }
            errorFeedback &+= 1
        }
    }
}

// MARK: - Tool policy

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

// MARK: - About

struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    IconTile(systemName: "sparkles", tint: .accentColor, size: 44, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detour").font(.title3.weight(.semibold))
                        Text("Built on Swoosh · Thin client to swooshd")
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
