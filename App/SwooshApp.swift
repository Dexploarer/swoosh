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
import SwooshDaemon
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

    /// In-process agent runtime + HTTP server. The app *is* the daemon now —
    /// there is no separate `swooshd`. Retained for the app's lifetime;
    /// quitting the app tears the kernel + server down with the process.
    @State private var daemonHandle: DaemonHandle?

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
                await bootInProcessDaemon()
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
        MenuBarTray(shell: shell) {
            codexBarHost.makeUsagePanel()
        }
    }

    // MARK: - In-process daemon

    /// Boot the agent runtime + HTTP server inside this process. Frees a
    /// stale :8787 first (e.g. a leftover from a previous app instance).
    /// On success the app's existing loopback HTTP client (wired by
    /// `bootLocalDaemon`) talks to the in-process server. On failure the
    /// UI degrades to its normal offline state — we still call
    /// `bootLocalDaemon` so the chat send-handler is wired.
    @MainActor
    private func bootInProcessDaemon() async {
        Self.freePort(8787)
        do {
            daemonHandle = try await SwooshDaemon.start(host: "0.0.0.0")
        } catch {
            let detail = "\(error)"
            NSLog("[Swoosh] in-process daemon failed to start: \(detail)")
            if detail.contains("Address already in use") || detail.contains("EADDRINUSE") {
                NSLog("[Swoosh] Port 8787 is still held after SIGTERM — likely another "
                    + "Swoosh instance. Quit it (or `lsof -ti:8787 | xargs kill`) then relaunch.")
            }
        }
    }

    /// Best-effort single-shot: SIGTERM whatever holds `port`, then wait
    /// briefly. Not a retry loop — if SIGTERM doesn't free it, a live
    /// process owns it and the start() error path surfaces that.
    private static func freePort(_ port: Int) {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti:\(port)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice
        guard (try? lsof.run()) != nil else { return }
        lsof.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pids = (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGTERM) }
        Thread.sleep(forTimeInterval: 1.5)
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

