// Apps/SwooshiOS/IOSVoicePill.swift — iOS bottom voice pill
//
// iOS analog of the macOS BottomVoicePillScene. Doesn't use a separate
// window (iOS apps can't host them); instead lives as a floating
// capsule overlaid at the bottom of the chat surface.

import SwiftUI
import SwooshGenerativeUI
import SwooshUI

struct IOSVoicePill: View {
    @Bindable var voice: VoiceMode
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            micButton
            VoiceWaveformView(
                level: voice.shell.speech.audioLevel,
                active: voice.isListening,
                barCount: 8
            )
            .frame(width: 56)
            Text(statusLine)
                .font(.system(size: 12, design: voice.isListening ? .monospaced : .default))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            ttsToggle
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 56)
        .background(SwooshNeonTokens.Canvas.bg)
        .overlay(
            Capsule().strokeBorder(
                SwooshNeonTokens.Accent.cyan.opacity(
                    voice.isListening ? 0.7 : 0.3
                ),
                lineWidth: 1.5
            )
        )
        .clipShape(Capsule())
        .shadow(
            color: SwooshNeonTokens.Accent.cyan.opacity(
                voice.isListening ? 0.6 : 0.3
            ),
            radius: 18
        )
    }

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
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if voice.pushToTalk, !voice.isListening { voice.pressMicDown() }
                }
                .onEnded { _ in
                    if voice.pushToTalk, voice.isListening { voice.releaseMic() }
                }
        )
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
        .disabled(!voice.hasTTS)
    }

    private var statusLine: String {
        if voice.isListening, !voice.shell.speech.transcript.isEmpty {
            return voice.shell.speech.transcript
        }
        if let last = voice.shell.messages.last, last.role == .agent {
            return last.text
        }
        return voice.pushToTalk ? "Hold mic to talk" : "Listening…"
    }
}
