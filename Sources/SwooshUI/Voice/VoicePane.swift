// SwooshUI/Voice/VoicePane.swift — Dashboard tab for voice mode
//
// Rebuilt around the SwooshOrbView (macOS-native port of metasidd/Orb)
// as the hero centerpiece. The orb reacts to voice state: idle → subtle
// pulse, listening → energetic cyan/green glow, speaking → warm purple.
//
// Key commands:
//   ⇧⌥Space  — toggle voice mode on/off
//   ⌥Space   — summon the floating voice pill

#if os(macOS)

import SwiftUI
import SwooshGenerativeUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - Orb Theme Presets
// ═══════════════════════════════════════════════════════════════════

public enum OrbTheme: String, CaseIterable, Identifiable, Sendable {
    case siri, aurora, ember, ocean, nebula, sunset, matrix, phantom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .siri:    return "Siri"
        case .aurora:  return "Aurora"
        case .ember:   return "Ember"
        case .ocean:   return "Ocean"
        case .nebula:  return "Nebula"
        case .sunset:  return "Sunset"
        case .matrix:  return "Matrix"
        case .phantom: return "Phantom"
        }
    }

    public var backgroundColors: [Color] {
        switch self {
        case .siri:    return [.pink, .purple, .blue]
        case .aurora:  return [.cyan, .green, .teal]
        case .ember:   return [.red, .orange, .yellow]
        case .ocean:   return [.blue, .cyan, .indigo]
        case .nebula:  return [.purple, .pink, .indigo]
        case .sunset:  return [.orange, .pink, .purple]
        case .matrix:  return [.green, .mint, .teal]
        case .phantom: return [.gray, .white.opacity(0.6), .blue.opacity(0.3)]
        }
    }

    public var glowColor: Color {
        switch self {
        case .siri:    return .purple
        case .aurora:  return .cyan
        case .ember:   return .orange
        case .ocean:   return .cyan
        case .nebula:  return .pink
        case .sunset:  return .orange
        case .matrix:  return .green
        case .phantom: return .white
        }
    }

    /// Preview config for the theme picker thumbnails
    public var previewConfig: SwooshOrbConfiguration {
        SwooshOrbConfiguration(
            backgroundColors: backgroundColors,
            glowColor: glowColor,
            coreGlowIntensity: 0.8,
            showParticles: false,
            showShadow: false,
            speed: 30
        )
    }

    /// Full config for the main orb (idle/active state)
    public func activeConfig(intensity: Double = 0.5, speed: Double = 25) -> SwooshOrbConfiguration {
        SwooshOrbConfiguration(
            backgroundColors: backgroundColors.map { $0.opacity(0.7) },
            glowColor: glowColor,
            coreGlowIntensity: intensity,
            speed: speed
        )
    }

    public func idleConfig() -> SwooshOrbConfiguration {
        SwooshOrbConfiguration(
            backgroundColors: backgroundColors.map { $0.opacity(0.2) },
            glowColor: glowColor.opacity(0.3),
            coreGlowIntensity: 0.2,
            speed: 15
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Voice Pane
// ═══════════════════════════════════════════════════════════════════

public struct VoicePane: View {
    @Bindable var voice: VoiceMode
    let shell: AgentShellModel
    @Environment(\.swooshTheme) var theme
    @AppStorage("swoosh.voice.orbTheme") private var selectedThemeName: String = OrbTheme.aurora.rawValue

    private var selectedTheme: OrbTheme {
        OrbTheme(rawValue: selectedThemeName) ?? .aurora
    }

    public init(voice: VoiceMode, shell: AgentShellModel) {
        self.voice = voice
        self.shell = shell
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                orbHero
                themePicker
                    .padding(.top, 20)
                controls
                    .padding(.top, 20)
                settingsCard
                    .padding(.top, 28)
                recentCard
                    .padding(.top, 20)
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SwooshNeonTokens.Canvas.bg)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Orb hero
    // ─────────────────────────────────────────────────────────────────

    private var orbConfiguration: SwooshOrbConfiguration {
        let t = selectedTheme
        if voice.isListening {
            // Listening always uses the theme colors at full intensity
            return SwooshOrbConfiguration(
                backgroundColors: t.backgroundColors,
                glowColor: t.glowColor,
                coreGlowIntensity: 1.0,
                speed: 60
            )
        } else if voice.isSpeaking {
            // Speaking uses a purple-shifted variant of the theme
            return SwooshOrbConfiguration(
                backgroundColors: [.purple, .indigo] + [t.glowColor],
                glowColor: .purple,
                coreGlowIntensity: 0.85,
                speed: 45
            )
        } else if voice.isActive {
            return t.activeConfig(intensity: 0.5, speed: 25)
        } else {
            return t.idleConfig()
        }
    }

    private var orbHero: some View {
        VStack(spacing: 16) {
            // The Orb
            SwooshOrbView(configuration: orbConfiguration)
                .frame(width: orbSize, height: orbSize)
                .animation(.easeInOut(duration: 0.6), value: voice.isActive)
                .animation(.easeInOut(duration: 0.3), value: voice.isListening)
                .animation(.easeInOut(duration: 0.3), value: voice.isSpeaking)
                .onTapGesture {
                    voice.toggle()
                }
                .accessibilityLabel(voice.isActive ? "Stop voice mode" : "Start voice mode")

            // State label
            VStack(spacing: 4) {
                Text(stateLabel)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)

                Text(stateDetail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            // Live transcript while listening
            if shell.voice == .listening {
                liveTranscript
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private var orbSize: CGFloat {
        if voice.isListening { return 180 }
        if voice.isSpeaking { return 160 }
        if voice.isActive { return 150 }
        return 140
    }

    private var liveTranscript: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.7), radius: 3)
            Text(shell.speech.transcript.isEmpty ? "Listening…" : shell.speech.transcript)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                .lineLimit(2)
                .truncationMode(.head)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.green.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.green.opacity(0.2), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: 400)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Theme picker
    // ─────────────────────────────────────────────────────────────────

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ORB THEME")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(OrbTheme.allCases) { orbTheme in
                        let isSelected = orbTheme == selectedTheme
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedThemeName = orbTheme.rawValue
                            }
                        } label: {
                            VStack(spacing: 6) {
                                SwooshOrbView(configuration: orbTheme.previewConfig)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                isSelected ? SwooshNeonTokens.Accent.cyan : Color.clear,
                                                lineWidth: 2
                                            )
                                            .frame(width: 50, height: 50)
                                    }

                                Text(orbTheme.label)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(
                                        isSelected
                                            ? SwooshNeonTokens.Accent.cyan
                                            : SwooshNeonTokens.Canvas.text3
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Controls row
    // ─────────────────────────────────────────────────────────────────

    private var controls: some View {
        HStack(spacing: 12) {
            // Start / Stop button
            Button {
                voice.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: voice.isActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(voice.isActive ? "Stop" : "Start Voice Mode")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(voice.isActive ? Color.red : Color.cyan)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [.option, .shift])
            .help("⇧⌥Space")

            // Hotkey hints
            HStack(spacing: 8) {
                hotkeyChip("⌥Space", "Voice pill")
                hotkeyChip("⇧⌥Space", "Toggle")
            }
        }
    }

    private func hotkeyChip(_ keys: String, _ desc: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(SwooshNeonTokens.Canvas.text1.opacity(0.8))
            Text(desc)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SwooshNeonTokens.Canvas.text1.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(SwooshNeonTokens.Canvas.text1.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Settings card
    // ─────────────────────────────────────────────────────────────────

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                settingRow(
                    icon: "speaker.wave.2",
                    title: "Speak agent replies",
                    detail: voice.hasTTS
                        ? "Agent answers are read aloud via the configured TTS voice."
                        : "No TTS engine configured.",
                    isOn: $voice.speakReplies
                )
                .disabled(!voice.hasTTS)

                settingDivider

                settingRow(
                    icon: "hand.point.up.left.fill",
                    title: "Push to talk",
                    detail: voice.pushToTalk
                        ? "Hold to record. Release to send."
                        : "Hands-free. STT runs continuously.",
                    isOn: $voice.pushToTalk
                )

                settingDivider

                settingRow(
                    icon: "rectangle.on.rectangle.angled",
                    title: "Desktop overlay",
                    detail: "Render agent UI surfaces on the desktop.",
                    isOn: $voice.projectToDesktop
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SwooshNeonTokens.Canvas.text1.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(SwooshNeonTokens.Line.rule, lineWidth: 0.5)
                    )
            )
        }
    }

    private var settingDivider: some View {
        Rectangle()
            .fill(SwooshNeonTokens.Line.rule)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }

    private func settingRow(
        icon: String, title: String, detail: String, isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SwooshNeonTokens.Accent.cyan)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
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

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Recent card
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)

            let last = shell.messages.suffix(6)
            if last.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundStyle(SwooshNeonTokens.Accent.cyan.opacity(0.2))
                        Text("No conversation yet. Start voice mode.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(spacing: 4) {
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
                .foregroundStyle(isUser ? .yellow : SwooshNeonTokens.Accent.cyan)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(isUser ? "You" : "Detour")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text3)
                Text(message.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(SwooshNeonTokens.Canvas.text1)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            Text(message.timestamp, style: .relative)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SwooshNeonTokens.Canvas.text3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SwooshNeonTokens.Canvas.text1.opacity(0.02))
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Derived
    // ─────────────────────────────────────────────────────────────────

    private var stateLabel: String {
        if !voice.isActive { return "Voice mode is off" }
        if voice.isListening { return "Listening" }
        if voice.isSpeaking { return "Speaking" }
        return "Ready"
    }

    private var stateDetail: String {
        if !voice.isActive { return "Tap the orb or press ⇧⌥Space to start." }
        if voice.isListening { return "Speak now. Detour is listening." }
        if voice.isSpeaking { return "Detour is reading the reply aloud." }
        return voice.pushToTalk
            ? "Push to talk: hold ⌥Space or the dock icon."
            : "Hands-free mode — listening after silence."
    }
}

#endif
