// SwooshUI/Voice/VoicePane.swift — Dashboard tab for voice mode
//
// Surfaces the existing `VoiceMode` actor + `SpeechCapture` + `TTSEngine`
// as a first-class dashboard tab instead of a hotkey-only floating pill.
// Three regions:
//   • Hero — current state, large mic toggle, live transcript while STT
//     is hot, hotkey hint.
//   • Settings — speak replies, push-to-talk vs hands-free, desktop
//     overlay projection, presentation surface.
//   • Recent — last few user / agent turns so the user can see what's
//     just happened without leaving the tab.
//
// Reads from `VoiceMode` (which is `@Observable`) and `AgentShellModel`.
// Toggles call methods on `VoiceMode`; no direct STT/TTS plumbing here.

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

public struct VoicePane: View {
    @Bindable var voice: VoiceMode
    let shell: AgentShellModel
    @Environment(\.swooshTheme) var theme

    public init(voice: VoiceMode, shell: AgentShellModel) {
        self.voice = voice
        self.shell = shell
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                Divider().opacity(0.2)
                settings
                Divider().opacity(0.2)
                recent
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Voice")
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(stateColor.opacity(0.18))
                    Circle()
                        .strokeBorder(stateColor.opacity(0.5), lineWidth: 1)
                    Image(systemName: stateIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(stateColor)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stateLabel)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(stateDetail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.66))
                }

                Spacer()

                Button {
                    voice.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: voice.isActive ? "stop.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(voice.isActive ? "Stop Voice Mode" : "Start Voice Mode")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(voice.isActive ? Color.red : Color.cyan)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [.option, .shift])
                .help("⇧⌥Space")
            }

            // Live transcript while STT is hot.
            if shell.voice == .listening {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LISTENING")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.green)
                    Text(shell.speech.transcript.isEmpty ? "…" : shell.speech.transcript)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.green.opacity(0.22), lineWidth: 1)
                                )
                        )
                }
            }

            // Hotkey hint.
            HStack(spacing: 12) {
                hotkeyHint("⌥Space", "Summon voice pill")
                hotkeyHint("⇧⌥Space", "Toggle voice mode")
            }
        }
    }

    private var stateIcon: String {
        if !voice.isActive { return "mic.slash" }
        if voice.isListening { return "waveform" }
        if voice.isSpeaking { return "speaker.wave.2.fill" }
        return "mic.fill"
    }

    private var stateColor: Color {
        if !voice.isActive { return .secondary }
        if voice.isListening { return .green }
        if voice.isSpeaking { return .cyan }
        return .yellow
    }

    private var stateLabel: String {
        if !voice.isActive { return "Voice mode is off" }
        if voice.isListening { return "Listening" }
        if voice.isSpeaking { return "Speaking" }
        return "Ready"
    }

    private var stateDetail: String {
        if !voice.isActive { return "Tap Start Voice Mode or press ⇧⌥Space." }
        if voice.isListening { return "Speak now. STT is hot." }
        if voice.isSpeaking { return "Agent is speaking the last reply." }
        return voice.pushToTalk
            ? "Push to talk: hold the pill, the dock icon, or ⌥Space."
            : "Hands-free: STT will pick up after each silence gap."
    }

    private func hotkeyHint(_ keys: String, _ desc: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textPrimary.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.textPrimary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(theme.textPrimary.opacity(0.18), lineWidth: 0.5)
                        )
                )
            Text(desc)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.62))
        }
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(theme.textPrimary.opacity(0.55))

            VStack(spacing: 0) {
                voiceToggleRow(
                    icon: "speaker.wave.2",
                    title: "Speak agent replies",
                    detail: voice.hasTTS
                        ? "Agent answers are read aloud via the configured TTS voice."
                        : "No TTS engine configured — set one in Settings → Voice to enable.",
                    isOn: $voice.speakReplies
                )
                .disabled(!voice.hasTTS)

                Divider().opacity(0.15).padding(.leading, 38)

                voiceToggleRow(
                    icon: "hand.point.up.left.fill",
                    title: "Push to talk",
                    detail: voice.pushToTalk
                        ? "Hold to record. Release to send."
                        : "Hands-free. STT runs continuously; silence gaps end utterances.",
                    isOn: $voice.pushToTalk
                )

                Divider().opacity(0.15).padding(.leading, 38)

                voiceToggleRow(
                    icon: "rectangle.on.rectangle.angled",
                    title: "Project to desktop overlay",
                    detail: "Render agent-generated UI surfaces on the desktop while voice mode is active.",
                    isOn: $voice.projectToDesktop
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.textPrimary.opacity(0.04))
            )
        }
    }

    private func voiceToggleRow(
        icon: String, title: String, detail: String, isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 22, height: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Recent

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(theme.textPrimary.opacity(0.55))

            let last = shell.messages.suffix(4)
            if last.isEmpty {
                Text("No conversation yet. Start voice mode and say something.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.5))
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(last), id: \.id) { msg in
                        recentRow(message: msg)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentRow(message: AgentShellMessage) -> some View {
        let isUser = (message.role == .user)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isUser ? "person.crop.circle" : "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isUser ? .yellow : theme.accent)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(isUser ? "You" : "Detour")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(theme.textPrimary.opacity(0.62))
                Text(message.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(message.timestamp, style: .relative)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textPrimary.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.textPrimary.opacity(0.03))
        )
    }
}

#endif
