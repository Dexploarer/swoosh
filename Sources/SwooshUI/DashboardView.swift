// SwooshUI/DashboardView.swift — Native Swoosh dashboard
//
// Not a demo. The real agent control panel.

import SwiftUI
import SwooshCore
import SwooshVault
import SwooshFirewall
import SwooshBoard
import SwooshFlow
import Foundation

public struct DashboardView: View {
    @State private var themeManager = ThemeManager()
    @State private var selectedTab: DashboardTab = .chat

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
                .swooshGlass()
        } detail: {
            detailView
        }
        .swooshGlassContainer()
        .swooshTheme(themeManager.currentTheme)
        .onAppear {
            // Load user theme from ~/.swoosh/theme.json
            let themeURL = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".swoosh/theme.json")
            themeManager.load(from: themeURL)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Section("Agent") {
                Label("Chat", systemImage: "bubble.left.and.bubble.right").tag(DashboardTab.chat)
                Label("Agents", systemImage: "person.3").tag(DashboardTab.agents)
            }

            Section("Work") {
                Label("Board", systemImage: "square.grid.3x3").tag(DashboardTab.board)
                Label("Workflows", systemImage: "arrow.triangle.branch").tag(DashboardTab.workflows)
                Label("Triggers", systemImage: "bolt").tag(DashboardTab.triggers)
            }

            Section("Knowledge") {
                Label("Memory Vault", systemImage: "brain.head.profile").tag(DashboardTab.vault)
                Label("Skills", systemImage: "star").tag(DashboardTab.skills)
            }

            Section("System") {
                Label("Tools", systemImage: "wrench.and.screwdriver").tag(DashboardTab.tools)
                Label("Firewall", systemImage: "shield.checkered").tag(DashboardTab.firewall)
                Label("Providers", systemImage: "cloud").tag(DashboardTab.providers)
                Label("Local Models", systemImage: "cpu").tag(DashboardTab.localModels)
                Label("MCP", systemImage: "cable.connector").tag(DashboardTab.mcp)
                Label("Plugins", systemImage: "puzzlepiece").tag(DashboardTab.plugins)
            }

            Section("Observe") {
                Label("Approvals", systemImage: "hand.raised").tag(DashboardTab.approvals)
                Label("Audit Log", systemImage: "list.bullet.rectangle").tag(DashboardTab.auditLog)
                Label("Benchmarks", systemImage: "chart.bar").tag(DashboardTab.benchmarks)
            }

            Section {
                Label("Appearance", systemImage: "paintbrush").tag(DashboardTab.appearance)
                Label("Settings", systemImage: "gear").tag(DashboardTab.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Swoosh")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .chat:        PlaceholderPane(title: "Chat", icon: "bubble.left.and.bubble.right")
        case .agents:      PlaceholderPane(title: "Active Agents", icon: "person.3")
        case .board:       PlaceholderPane(title: "Swoosh Board", icon: "square.grid.3x3")
        case .workflows:   PlaceholderPane(title: "Workflows", icon: "arrow.triangle.branch")
        case .triggers:    PlaceholderPane(title: "Triggers", icon: "bolt")
        case .vault:       PlaceholderPane(title: "Memory Vault", icon: "brain.head.profile")
        case .skills:      PlaceholderPane(title: "Skills", icon: "star")
        case .tools:       PlaceholderPane(title: "Tools", icon: "wrench.and.screwdriver")
        case .firewall:    PlaceholderPane(title: "Agent Firewall", icon: "shield.checkered")
        case .providers:   ProviderStatusPane()
        case .localModels: PlaceholderPane(title: "Local Models", icon: "cpu")
        case .mcp:         PlaceholderPane(title: "MCP Servers", icon: "cable.connector")
        case .plugins:     PlaceholderPane(title: "Plugins", icon: "puzzlepiece")
        case .approvals:   PlaceholderPane(title: "Approval Center", icon: "hand.raised")
        case .auditLog:    PlaceholderPane(title: "Audit Log", icon: "list.bullet.rectangle")
        case .benchmarks:  PlaceholderPane(title: "Benchmarks", icon: "chart.bar")
        case .appearance:  AppearancePane(themeManager: themeManager)
        case .settings:    PlaceholderPane(title: "Settings", icon: "gear")
        }
    }
}

// MARK: - Tab enum

enum DashboardTab: Hashable {
    case chat, agents, board, workflows, triggers
    case vault, skills
    case tools, firewall, providers, localModels, mcp, plugins
    case approvals, auditLog, benchmarks
    case appearance, settings
}

// MARK: - Placeholder pane

struct PlaceholderPane: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
    }
}

// MARK: - Appearance pane (full theme editor)

struct AppearancePane: View {
    @Bindable var themeManager: ThemeManager

    @State private var rawJSON: String = ""
    @State private var parseError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Appearance")
                    .font(.largeTitle.bold())

                Text("Edit ~/.swoosh/theme.json or use the editor below. Changes apply in real time.")
                    .foregroundStyle(.secondary)

                // Live JSON editor
                GroupBox("theme.json") {
                    TextEditor(text: $rawJSON)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 350)
                        .onChange(of: rawJSON) { _, newValue in
                            themeManager.update(fromJSON: newValue)
                        }
                }
                .swooshGlass()

                if let err = parseError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack {
                    Button("Save to disk") {
                        let url = FileManager.default.homeDirectoryForCurrentUser
                            .appending(path: ".swoosh/theme.json")
                        try? themeManager.save(to: url)
                    }
                    .buttonStyle(.glass)

                    Button("Reset to defaults") {
                        themeManager.update(with: .liquidGlassDefault)
                        refreshJSON()
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(32)
        }
        .navigationTitle("Appearance")
        .onAppear { refreshJSON() }
    }

    private func refreshJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(themeManager.currentTheme.config),
           let str = String(data: data, encoding: .utf8) {
            rawJSON = str
        }
    }
}

#Preview {
    DashboardView()
}
