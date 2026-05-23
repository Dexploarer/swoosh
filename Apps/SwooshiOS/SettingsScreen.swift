// Apps/SwooshiOS/SettingsScreen.swift
// Version: 0.9R
//
// Sectioned settings hub. Top-level list of icon-tile rows, each pushing
// to a dedicated detail screen (Pairing, Permission profile, Safety
// flags, Tool policy, Capabilities, Voice, About). Detail screens live
// in PairingDetailScreen.swift and PermissionAndPolicyScreens.swift so
// this root stays under the LOC convention.

import SwiftUI
import SwooshClient

struct SettingsScreen: View {
    @Environment(ClientSession.self) private var session
    @State private var isRefreshing = false

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

            Section("Local model") {
                LocalFallbackToggleRow()
                LocalModelDownloadRow()
            }

            Section("Voice") {
                NavigationLink {
                    VoicePickerScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "waveform", tint: .cyan),
                        title: "Speech & Voice",
                        detail: "STT engine, TTS provider, voice picker"
                    )
                }
            }

            Section("Capabilities") {
                NavigationLink {
                    CapabilityPickerScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "wand.and.rays", tint: .purple),
                        title: "Vision, Translation, Embeddings, Image gen",
                        detail: capabilitiesDetail
                    )
                }
            }

            Section("Automation") {
                NavigationLink {
                    CronScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "calendar.badge.clock", tint: .indigo),
                        title: "Scheduled jobs",
                        detail: "Cron-style triggers that wake the agent"
                    )
                }
            }

            Section("Diagnostics") {
                NavigationLink {
                    DoctorScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "stethoscope", tint: .red),
                        title: "Doctor",
                        detail: "System health, config, secrets, model, storage"
                    )
                }
            }

            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    IconRow(
                        tile: IconTile(systemName: "info.circle", tint: .gray),
                        title: "About Detour"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .task { await refreshStatus() }
        .refreshable { await refreshStatus() }
    }

    private func refreshStatus() async {
        guard session.isPaired else { return }
        withAnimation(.easeOut(duration: 0.22)) { isRefreshing = true }
        await session.refresh()
        withAnimation(.easeOut(duration: 0.22)) { isRefreshing = false }
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
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
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

    private var capabilitiesDetail: String {
        "Local-first routing, cloud fallback when configured"
    }
}
