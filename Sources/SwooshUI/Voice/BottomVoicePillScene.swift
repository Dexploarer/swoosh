// SwooshUI/Voice/BottomVoicePillScene.swift — 0.9R Bottom-anchored voice pill
//
// Frameless floating panel pinned to the bottom-center of the screen
// while voice mode is active. Wider and squatter than the top ⌥Space
// pill — designed to peek from the bottom of the screen the way
// macOS's Siri orb used to.
//
// Layout:
//   ┌─ glow border ──────────────────────────────────────────────┐
//   │  🎤 [waveform]   live transcript or reply             [✕]  │
//   └────────────────────────────────────────────────────────────┘
//
// Press-and-hold on the mic mirrors push-to-talk semantics. Tap [✕]
// exits voice mode (different from "dismiss the window" — uses the
// VoiceMode stop method so the orchestrator unwinds cleanly).

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

public struct BottomVoicePillScene: Scene {

    public static let windowID: String = "swoosh.voice-pill-bottom"

    private let voice: VoiceMode

    public init(voice: VoiceMode) {
        self.voice = voice
    }

    public var body: some Scene {
        Window("Swoosh Voice (bottom)", id: Self.windowID) {
            BottomVoicePillContainer(voice: voice)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.bottom)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct BottomVoicePillContainer: View {
    @Bindable var voice: VoiceMode

    @Bindable private var ttsBindable: TTSEngineBindableProxy

    init(voice: VoiceMode) {
        self.voice = voice
        self.ttsBindable = TTSEngineBindableProxy(engine: voice.tts)
    }

    var body: some View {
        HStack(spacing: SwooshNeonTokens.Spacing.base) {
            micButton
            waveform
            statusText
            Spacer(minLength: 8)
            sendButton
            ttsToggle
            exitButton
        }
        .padding(.horizontal, SwooshNeonTokens.Spacing.base + 4)
        .padding(.vertical, SwooshNeonTokens.Spacing.micro + 2)
        .frame(width: 560, height: 64)
        .background(SwooshNeonTokens.Canvas.bg)
        .overlay(
            Capsule()
                .strokeBorder(
                    SwooshNeonTokens.Accent.cyan.opacity(
                        voice.isListening
                            ? SwooshNeonTokens.Line.bright
                            : SwooshNeonTokens.Line.dim * 2
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(Capsule())
        .shadow(
            color: SwooshNeonTokens.Accent.cyan.opacity(
                voice.isListening
                    ? SwooshNeonTokens.Glow.active
                    : SwooshNeonTokens.Glow.focus
            ),
            radius: SwooshNeonTokens.Glow.radius
        )
        .padding(SwooshNeonTokens.Spacing.base)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.15), value: voice.isListening)
    }

    // MARK: - Pieces

    private var micButton: some View {
        Button { } label: {
            ZStack {
                ListeningPulse(active: voice.isListening)
                Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(voice.isListening
                        ? SwooshNeonTokens.Accent.cyan
                        : SwooshNeonTokens.Canvas.text2)
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(SwooshNeonTokens.Canvas.bg))
            .overlay(
                Circle().strokeBorder(
                    SwooshNeonTokens.Accent.cyan.opacity(
                        voice.isListening
                            ? SwooshNeonTokens.Line.bright
                            : SwooshNeonTokens.Line.dim * 2
                    ),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        // Press-and-hold gesture for push-to-talk.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if voice.pushToTalk, !voice.isListening { voice.pressMicDown() }
                }
                .onEnded { _ in
                    if voice.pushToTalk, voice.isListening { voice.releaseMic() }
                }
        )
        .accessibilityLabel(voice.isListening ? "Release to send" : "Hold to talk")
    }

    private var waveform: some View {
        VoiceWaveformView(
            level: voice.shell.speech.audioLevel,
            active: voice.isListening,
            barCount: 10
        )
        .frame(width: 60)
    }

    private var statusText: some View {
        Text(statusLine)
            .font(.system(size: 12, design: voice.isListening ? .monospaced : .default))
            .foregroundStyle(SwooshNeonTokens.Canvas.text1)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: 220, alignment: .leading)
    }

    private var statusLine: String {
        if voice.isListening, !voice.shell.speech.transcript.isEmpty {
            return voice.shell.speech.transcript
        }
        if ttsBindable.isSpeaking, let speaking = ttsBindable.currentText {
            return "🔊 \(speaking)"
        }
        if let last = voice.shell.messages.last, last.role == .agent {
            return last.text
        }
        return voice.pushToTalk ? "Hold mic to talk" : "Listening…"
    }

    @ViewBuilder
    private var sendButton: some View {
        if !voice.shell.input.isEmpty && !voice.isListening {
            Button {
                Task { await voice.submitAndMaybeSpeak() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(SwooshNeonTokens.Accent.cyan)
            }
            .buttonStyle(.plain)
        }
    }

    private var ttsToggle: some View {
        Button {
            voice.speakReplies.toggle()
        } label: {
            Image(systemName: voice.speakReplies ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13))
                .foregroundStyle(voice.speakReplies
                    ? SwooshNeonTokens.Accent.cyan
                    : SwooshNeonTokens.Canvas.text3)
        }
        .buttonStyle(.plain)
        .help(voice.speakReplies ? "TTS on" : "TTS off")
        .disabled(!voice.hasTTS)
    }

    private var exitButton: some View {
        Button { voice.stop() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .buttonStyle(.plain)
        .help("Exit voice mode")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - TTS Bindable proxy
// ═══════════════════════════════════════════════════════════════════

/// Wraps an optional TTSEngine so the View can observe it via @Bindable
/// without crashing when no engine is attached.
@MainActor
@Observable
final class TTSEngineBindableProxy {
    let engine: TTSEngine?

    var isSpeaking: Bool { engine?.isSpeaking ?? false }
    var currentText: String? { engine?.currentText }

    init(engine: TTSEngine?) {
        self.engine = engine
    }
}

#endif
