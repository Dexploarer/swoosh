// App/SwooshApp.swift — Unified Swoosh macOS application
//
// One process, one app, one kernel. The dashboard is the primary surface,
// the menu-bar extra is a secondary convenience. On launch:
//   1. Boot the local daemon client (connects to swooshd at 127.0.0.1:8787)
//   2. Open the dashboard window
//   3. Show a menu-bar icon for quick access
//
// This replaces the old split between SwooshApp (menu-bar only),
// SwooshMacApp (standalone dashboard), and swooshd (headless daemon).

import SwiftUI
import AppKit
import SwooshUI
import SwooshSecrets
import SwooshWidgets
import CodexBar

@main
struct SwooshApp: App {
    /// Single shell instance backing every scene.
    @State private var shell = AgentShellModel()
    @State private var didBoot = false

    /// TTS engine (independent — voice mode works without it).
    @State private var tts = TTSEngine()

    /// Voice mode orchestrator. Holds the on/off state + STT + TTS wiring.
    @State private var voice: VoiceMode

    /// Global hotkey. ⇧⌥Space = toggle voice mode.
    @State private var voiceModeHotKey: GlobalHotKey?

    /// CodexBar opaque host handle — owns the usage store + settings.
    private let codexBarHost: CodexBarHost

    init() {
        SwooshTipsConfigurator.configure()

        // ── CodexBar bootstrap (creates stores internally) ──
        let cbHost = CodexBarHost.bootstrap()

        let shell = AgentShellModel()
        let tts = TTSEngine()
        _shell = State(initialValue: shell)
        _tts = State(initialValue: tts)
        _voice = State(initialValue: VoiceMode(shell: shell, tts: tts))
        self.codexBarHost = cbHost
    }

    var body: some Scene {
        // ── Full dashboard window (primary surface) ──
        Window("Detour", id: "dashboard") {
            DashboardHost(shell: shell, voice: voice) {
                guard !didBoot else { return }
                didBoot = true
                installGlobalHotKeys()
                await AgentShellBackends.bootLocalDaemon(shell: shell)
            }
        }
        .defaultSize(width: 1200, height: 800)
        .defaultLaunchBehavior(.presented)
        .commands {
            SwooshEditCommands()
        }

        // ── Menu bar icon ──
        MenuBarExtra {
            menuBarContent
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
        // ── Desktop generative-UI overlay ──
        DesktopOverlayScene(shell: shell)

        // ── Settings window ──
        Settings {
            codexBarHost.makePreferencesView()
        }
    }

    // MARK: - Menu bar

    @ViewBuilder
    private var menuBarLabel: some View {
        Image(systemName: voice.isActive ? "waveform.circle.fill" : "sparkles")
    }

    @ViewBuilder
    private var menuBarContent: some View {
        codexBarHost.makeTrayTabView {
            AgentShellView(shell: shell, mode: .tray)
        }
        .frame(width: 400, height: 520)
    }

    // MARK: - Hotkeys

    @MainActor
    private func installGlobalHotKeys() {
        if voiceModeHotKey == nil {
            voiceModeHotKey = GlobalHotKey(key: .space, modifiers: [.option, .shift]) {
                NotificationCenter.default.post(name: .swooshToggleVoiceMode, object: nil)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification names
// ═══════════════════════════════════════════════════════════════════

extension Notification.Name {
    /// Toggle persistent voice mode (the bottom pill + STT + TTS + overlay).
    static let swooshToggleVoiceMode = Notification.Name("ai.swoosh.toggleVoiceMode")
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Dashboard host (notification → voice bridge)
// ═══════════════════════════════════════════════════════════════════

/// Wrapper view so global hotkey notifications can toggle voice mode.
private struct DashboardHost: View {
    @Bindable var shell: AgentShellModel
    var voice: VoiceMode
    var onBoot: @MainActor () async -> Void

    var body: some View {
        DashboardView(shell: shell, voice: voice)
            .frame(minWidth: 800, minHeight: 600)
            .onReceive(NotificationCenter.default.publisher(for: .swooshToggleVoiceMode)) { _ in
                voice.toggle()
            }
            .task {
                await onBoot()
            }
    }
}

