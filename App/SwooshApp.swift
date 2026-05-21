// App/SwooshApp.swift — Main Swoosh macOS application
//
// Five scenes share one AgentShellModel:
//   • Tray popover                — MenuBarExtra (default surface)
//   • Voice pill (top, ⌥Space)    — frameless summoned capsule
//   • Voice pill (bottom)         — anchored, persists while voice mode is on
//   • Desktop overlay             — projects agent-emitted UI to the desktop
//   • Dashboard window            — full-screen agent control panel
//
// VoiceMode coordinates STT + agent + TTS + overlay. Each subsystem is
// independent: no TTS engine = no spoken replies; no overlay = surfaces
// render in the pill; no mic = text-only.

import SwiftUI
import AppKit
import SwooshUI
import SwooshSecrets
import SwooshWidgets

@main
struct SwooshApp: App {
    @State private var menuBarManager = MenuBarManager(preset: .swoosh)
    @State private var themeManager = ThemeManager()

    /// Single shell instance backing every scene.
    @State private var shell = AgentShellModel()
    @State private var didBoot = false

    /// TTS engine (independent — voice mode works without it).
    @State private var tts = TTSEngine()

    /// Voice mode orchestrator. Holds the on/off state + STT + TTS wiring.
    @State private var voice: VoiceMode

    /// Global hotkeys. ⌥Space = top pill; ⇧⌥Space = toggle voice mode.
    @State private var pillHotKey: GlobalHotKey?
    @State private var voiceModeHotKey: GlobalHotKey?

    init() {
        SwooshTipsConfigurator.configure()
        let shell = AgentShellModel()
        let tts = TTSEngine()
        _shell = State(initialValue: shell)
        _tts = State(initialValue: tts)
        _voice = State(initialValue: VoiceMode(shell: shell, tts: tts))
    }

    var body: some Scene {
        // ── Menu bar icon + popover ──
        MenuBarExtra {
            MenuBarRoot(
                manager: menuBarManager,
                themeManager: themeManager,
                shell: shell,
                voice: voice,
                onBoot: {
                    if !didBoot {
                        didBoot = true
                        await AgentShellBackends.bootLocalDaemon(shell: shell)
                        installGlobalHotKeys()
                    }
                    await menuBarManager.refreshCredentials()
                }
            )
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // ── Top voice pill (⌥Space) ──
        VoicePillScene(shell: shell)

        // ── Bottom voice pill (voice mode is on) ──
        BottomVoicePillScene(voice: voice)

        // ── Desktop generative-UI overlay (voice mode is on) ──
        DesktopOverlayScene(shell: shell)

        // ── Full dashboard window ──
        Window("Swoosh", id: "dashboard") {
            DashboardView()
                .environment(shell)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SwooshEditCommands()
            SwooshShellCommands(voice: voice)
        }

        // ── Settings window ──
        Settings {
            MenuBarCustomizerView(manager: menuBarManager)
                .swooshTheme(themeManager.currentTheme)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch menuBarManager.config.iconMode {
        case .swooshLogo:
            Image(systemName: voice.isActive ? "waveform.circle.fill" : "sparkles")
        case .providerMeter:
            Image(systemName: "chart.bar.fill")
        case .statusDot:
            Image(systemName: statusDotIcon)
        case .providerIcon:
            Image(systemName: "cloud.fill")
        case .custom:
            Image(systemName: menuBarManager.config.customIconName ?? "sparkles")
        }
    }

    private var statusDotIcon: String {
        let hasIssues = menuBarManager.providerStatuses.contains { !$0.isHealthy }
        return hasIssues ? "circle.fill" : "circle.fill"
    }

    @MainActor
    private func installGlobalHotKeys() {
        if pillHotKey == nil {
            pillHotKey = GlobalHotKey(key: .space, modifiers: [.option]) {
                NotificationCenter.default.post(name: .swooshShowVoicePill, object: nil)
            }
        }
        if voiceModeHotKey == nil {
            // ⇧⌥Space toggles persistent voice mode (the bottom pill).
            voiceModeHotKey = GlobalHotKey(key: .space, modifiers: [.option, .shift]) {
                NotificationCenter.default.post(name: .swooshToggleVoiceMode, object: nil)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Menu bar root
// ═══════════════════════════════════════════════════════════════════

/// MenuBarExtra content wrapper. Hosts the popover, runs the one-shot
/// boot task, and observes all show/hide notifications so the appropriate
/// pill / overlay opens from any source (global hotkey, menu, agent).
private struct MenuBarRoot: View {
    @Bindable var manager: MenuBarManager
    @Bindable var themeManager: ThemeManager
    let shell: AgentShellModel
    let voice: VoiceMode
    let onBoot: () async -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        MenuBarPopoverView(manager: manager)
            .swooshTheme(themeManager.currentTheme)
            .environment(shell)
            .task { await onBoot() }
            // Top pill (⌥Space)
            .onReceive(NotificationCenter.default.publisher(for: .swooshShowVoicePill)) { _ in
                openWindow(id: VoicePillScene.windowID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .swooshHideVoicePill)) { _ in
                dismissWindow(id: VoicePillScene.windowID)
            }
            // Voice mode toggle
            .onReceive(NotificationCenter.default.publisher(for: .swooshToggleVoiceMode)) { _ in
                voice.toggle()
            }
            // Bottom pill mount/unmount
            .onReceive(NotificationCenter.default.publisher(for: .swooshShowVoicePillBottom)) { _ in
                openWindow(id: BottomVoicePillScene.windowID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .swooshHideVoicePillBottom)) { _ in
                dismissWindow(id: BottomVoicePillScene.windowID)
            }
            // Desktop overlay mount/unmount
            .onReceive(NotificationCenter.default.publisher(for: .swooshShowDesktopOverlay)) { _ in
                openWindow(id: DesktopOverlayScene.windowID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .swooshHideDesktopOverlay)) { _ in
                dismissWindow(id: DesktopOverlayScene.windowID)
            }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Shell commands
// ═══════════════════════════════════════════════════════════════════

private struct SwooshShellCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    let voice: VoiceMode

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Voice Pill") {
                openWindow(id: VoicePillScene.windowID)
            }
            .keyboardShortcut(.space, modifiers: [.option])

            Button("Hide Voice Pill") {
                dismissWindow(id: VoicePillScene.windowID)
            }
            .keyboardShortcut(.space, modifiers: [.option, .control])

            Button(voice.isActive ? "Stop Voice Mode" : "Start Voice Mode") {
                voice.toggle()
            }
            .keyboardShortcut(.space, modifiers: [.option, .shift])

            Toggle("Speak Replies (TTS)", isOn: Binding(
                get: { voice.speakReplies },
                set: { voice.speakReplies = $0 }
            ))
            .disabled(!voice.hasTTS)

            Toggle("Project to Desktop Overlay", isOn: Binding(
                get: { voice.projectToDesktop },
                set: { voice.projectToDesktop = $0 }
            ))

            Divider()

            Button("Open Dashboard") {
                openWindow(id: "dashboard")
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Toggle Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Local notification name (App-side only)
// ═══════════════════════════════════════════════════════════════════

extension Notification.Name {
    /// Toggle persistent voice mode (the bottom pill + STT + TTS + overlay).
    static let swooshToggleVoiceMode = Notification.Name("ai.swoosh.toggleVoiceMode")
}
