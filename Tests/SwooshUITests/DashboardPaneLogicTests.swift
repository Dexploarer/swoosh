// Tests/SwooshUITests/DashboardPaneLogicTests.swift
// Pure logic coverage for dashboard pane display helpers.

import Foundation
import Testing
@testable import SwooshUI

@Suite("Dashboard provider ordering")
struct DashboardProviderOrderingTests {
    @Test("Known providers are sorted before unknown providers")
    func knownProviderOrder() {
        let ordered = DashboardProviderOrdering.orderedIDs([
            "z-custom",
            "local-openai",
            "openrouter",
            "codex",
            "a-custom",
            "openai",
            "local-diagnostic",
            "mlx-local",
            "apple-foundation"
        ])

        #expect(ordered == [
            "codex",
            "openai",
            "openrouter",
            "apple-foundation",
            "mlx-local",
            "local-openai",
            "local-diagnostic",
            "z-custom",
            "a-custom"
        ])
    }
}

@Suite("Dashboard provider display")
struct DashboardProviderDisplayTests {
    @Test("Provider statuses use user-facing labels")
    func statusLabels() {
        #expect(DashboardProviderDisplay.statusLabel(for: "signed_in") == "Signed in")
        #expect(DashboardProviderDisplay.statusLabel(for: "missing_key") == "API key required")
        #expect(DashboardProviderDisplay.statusLabel(for: "active_until_model_provider_configured") == "Fallback (diagnostic)")
        #expect(DashboardProviderDisplay.statusLabel(for: "custom_state") == "Custom State")
    }

    @Test("API key support is limited to cloud key providers")
    func acceptsAPIKey() {
        #expect(DashboardProviderDisplay.acceptsAPIKey(providerID: "openai"))
        #expect(DashboardProviderDisplay.acceptsAPIKey(providerID: "openrouter"))
        #expect(!DashboardProviderDisplay.acceptsAPIKey(providerID: "codex"))
        #expect(!DashboardProviderDisplay.acceptsAPIKey(providerID: "local-openai"))
    }
}

@Suite("Local model display formatting")
struct LocalModelDisplayFormattingTests {
    @Test("Installed model subtitle joins present metadata")
    func installedSubtitle() {
        #expect(
            LocalModelDisplayFormatter.installedSubtitle(
                family: "gemma4",
                parameterSize: "4B",
                quantization: "Q4_K_M",
                isChatCapable: true
            ) == "Family: gemma4 · 4B · Q4_K_M"
        )

        #expect(
            LocalModelDisplayFormatter.installedSubtitle(
                family: nil,
                parameterSize: nil,
                quantization: nil,
                isChatCapable: false
            ) == "Embedding-only (not chat-capable)"
        )
    }

    @Test("Sizes and download counts are compact")
    func compactNumbers() {
        #expect(LocalModelDisplayFormatter.formattedDownloadCount(1_250_000) == "1M ↓")
        #expect(LocalModelDisplayFormatter.formattedDownloadCount(42_000) == "42k ↓")
        #expect(LocalModelDisplayFormatter.formattedDownloadCount(999) == "999 ↓")

        #expect(LocalModelDisplayFormatter.formattedSize(1_610_612_736) == "1.5 GB")
        #expect(LocalModelDisplayFormatter.formattedSize(524_288_000) == "500 MB")
        #expect(LocalModelDisplayFormatter.formattedSize(nil) == nil)
    }
}

@Suite("Panel layout presets")
@MainActor
struct PanelLayoutPresetTests {
    @Test("Dashboard default preset starts with the agent shell and live operations")
    func dashboardDefaultPreset() {
        let preset = PanelLayoutPreset.defaultPreset(for: "dashboard")
        let layout = preset.makeLayout(surface: "dashboard")

        #expect(preset.id == "dashboard.operator")
        #expect(layout.surface == "dashboard")
        #expect(Array(layout.panels.map(\.kind).prefix(5)) == [
            .agentShell,
            .approvals,
            .board,
            .goals,
            .workflows
        ])
    }

    @Test("iOS default preset keeps chat adjacent controls compact")
    func iosDefaultPreset() {
        let layout = PanelLayoutPreset.defaultPreset(for: "ios").makeLayout(surface: "ios")

        #expect(layout.panels.map(\.kind) == [
            .recentChats,
            .providerStatus,
            .approvals,
            .goals,
            .localModels,
            .skills,
            .voiceTranscript,
            .wallet
        ])
    }

    @Test("Applying a preset writes a fresh layout for the requested surface")
    func applyPreset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh_panel_layout_test_\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PanelLayoutStore(directory: directory)
        let preset = try #require(PanelLayoutPreset.options(for: "dashboard")
            .first { $0.id == "dashboard.observer" })

        store.applyPreset(preset, to: "dashboard")
        let layout = store.layout(for: "dashboard")

        #expect(layout.surface == "dashboard")
        #expect(layout.panels.map(\.kind) == preset.kinds)
        #expect(Set(layout.panels.map(\.id)).count == preset.kinds.count)
    }

    @Test("Empty persisted layouts fall back to the default preset")
    func emptyPersistedLayoutFallsBack() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh_panel_layout_empty_test_\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = PanelLayoutStore(directory: directory)
        writer.setLayout(PanelLayout(surface: "dashboard"))

        let reader = PanelLayoutStore(directory: directory)
        let layout = reader.layout(for: "dashboard")

        #expect(layout.panels.map(\.kind) == PanelLayoutPreset.dashboardOperator.kinds)
    }
}
