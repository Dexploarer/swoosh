// Apps/SwooshiOS/AgentRoot.swift — iOS chat surface backed by AgentShellView
//
// Replaces the standalone ChatScreen. Reuses the cross-platform
// AgentShellModel + AgentShellView, plumbs the iOS pairing client into
// `shell.send`, and renders a compact voice pill as a bottom sheet
// (iOS doesn't have floating windows the way macOS does).

import SwiftUI
import SwooshClient
import SwooshGenerativeUI
import SwooshUI
import SwooshVoiceProviders

struct AgentRoot: View {
    @Environment(ClientSession.self) private var session
    @State private var shell = AgentShellModel()
    @State private var tts = TTSEngine()
    @State private var voice: VoiceMode? = nil
    @State private var wiredExecutor = false
    @State private var showVoicePill = false

    let onOpenDrawer: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            shellSurface
            if showVoicePill, let voice {
                IOSVoicePill(voice: voice, onClose: { closePill() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(shell)
        .background(SwooshNeonTokens.Canvas.bg.ignoresSafeArea())
        .task { wireExecutor() }
        .onChange(of: session.isPaired) { _, _ in
            wiredExecutor = false
            wireExecutor()
        }
        .toolbar { toolbarContent }
        .animation(.spring(duration: 0.3), value: showVoicePill)
    }

    // MARK: - Shell

    private var shellSurface: some View {
        AgentShellView(shell: shell, mode: .window)
            .toolbar(.hidden, for: .navigationBar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onOpenDrawer) {
                Image(systemName: "line.3.horizontal")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                voice?.toggle()
                showVoicePill = voice?.isActive ?? false
            } label: {
                Image(systemName: showVoicePill ? "waveform.circle.fill" : "mic.fill")
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            }
        }
    }

    // MARK: - Wiring

    private func wireExecutor() {
        guard !wiredExecutor else { return }
        wiredExecutor = true
        if voice == nil {
            voice = VoiceMode(shell: shell, tts: tts)
        }
        guard let executor = session.executor() else {
            return
        }
        // Wrap shell.send: persist + route to executor + speak through
        // the user's currently-chosen cloud TTS (if configured). The
        // system fallback uses the existing AVSpeechSynthesizer path
        // via VoiceMode.speakReplies/TTSEngine.
        let baseHandler = AgentShellBackends.swooshExecutor(executor, sessionID: session.sessionID)
        shell.send = { @MainActor text, shellModel in
            await baseHandler(text, shellModel)
            // After the agent replies, route through the cloud TTS
            // when the user has picked one and key is configured.
            guard let lastReply = shellModel.messages.last,
                  lastReply.role == .agent,
                  VoiceRouter.shared.isCurrentTTSConfigured(),
                  VoiceRouter.shared.currentTTSChoice != .system,
                  let provider = try? VoiceRouter.shared.activeCloudTTSProvider()
            else { return }
            do {
                let stream = provider.synthesizeStream(
                    text: lastReply.text,
                    voiceID: nil,
                    format: .mp3
                )
                await VoiceRouter.shared.streamingPlayer.play(stream: stream, format: .mp3)
            } catch {
                // Fall back silently — the user still gets text + system voice.
            }
        }
    }

    private func closePill() {
        voice?.stop()
        showVoicePill = false
    }
}
