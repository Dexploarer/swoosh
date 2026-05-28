// SwooshUI/Gaming/GamingAgentOrb.swift — Floating agent orb overlay — 0.9U
//
// A draggable, floating SwooshOrbView that lives on top of the gaming pane.
// Tap to toggle voice mode. Long-press to open inline text chat.
//
// The orb reacts to voice state (idle, listening, speaking) and NitroGen
// status (running → green ring, error → red ring). It is wired to the
// real VoiceMode orchestrator so STT → Shell → TTS flows naturally.
//
// The orb is the user's primary way to talk to the main agent while gaming.
// Voice commands like "start playing" or "stop" route through AgentKernel
// which can invoke NitroGen tools.

#if os(macOS)

import SwiftUI

// ═══════════════════════════════════════════════════════════════════
// MARK: - GamingAgentOrb
// ═══════════════════════════════════════════════════════════════════

public struct GamingAgentOrb: View {
    @Bindable var voiceMode: VoiceMode
    var isNitroGenRunning: Bool = false

    // Draggable position — default bottom-left
    @State private var position: CGPoint = CGPoint(x: 52, y: 0)  // y set on appear
    @State private var dragOffset: CGSize = .zero
    @State private var isHovered: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var showChatBubble: Bool = false
    @State private var chatInput: String = ""

    private let orbIdleSize: CGFloat = 48
    private let orbActiveSize: CGFloat = 56
    private let orbListeningSize: CGFloat = 64

    public init(
        voiceMode: VoiceMode,
        isNitroGenRunning: Bool = false
    ) {
        self.voiceMode = voiceMode
        self.isNitroGenRunning = isNitroGenRunning
    }

    private var orbSize: CGFloat {
        if voiceMode.isListening { return orbListeningSize }
        if voiceMode.isActive { return orbActiveSize }
        return orbIdleSize
    }

    private var orbConfig: SwooshOrbConfiguration {
        if voiceMode.isListening {
            return SwooshOrbConfiguration(
                backgroundColors: [.cyan, .green, .teal],
                glowColor: .cyan,
                coreGlowIntensity: 1.0,
                showParticles: true,
                speed: 60
            )
        } else if voiceMode.isSpeaking {
            return SwooshOrbConfiguration(
                backgroundColors: [.purple, .indigo, .blue],
                glowColor: .purple,
                coreGlowIntensity: 0.85,
                speed: 45
            )
        } else if voiceMode.shell.isAwaitingResponse {
            // Agent is thinking — amber pulse
            return SwooshOrbConfiguration(
                backgroundColors: [.orange.opacity(0.8), .yellow.opacity(0.6), .red.opacity(0.5)],
                glowColor: .orange,
                coreGlowIntensity: 0.7,
                showParticles: true,
                speed: 50
            )
        } else if voiceMode.isActive {
            return SwooshOrbConfiguration(
                backgroundColors: [.cyan.opacity(0.7), .green.opacity(0.7), .teal.opacity(0.7)],
                glowColor: .cyan,
                coreGlowIntensity: 0.5,
                speed: 25
            )
        } else {
            return SwooshOrbConfiguration(
                backgroundColors: [.cyan.opacity(0.2), .blue.opacity(0.2), .purple.opacity(0.2)],
                glowColor: .cyan.opacity(0.3),
                coreGlowIntensity: 0.2,
                showParticles: false,
                speed: 15
            )
        }
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Orb ──────────────────────────────────────────
                VStack(spacing: 6) {
                    ZStack {
                        // NitroGen status ring
                        if isNitroGenRunning {
                            Circle()
                                .strokeBorder(Color.green.opacity(0.6), lineWidth: 2)
                                .frame(width: orbSize + 8, height: orbSize + 8)
                                .shadow(color: .green.opacity(0.4), radius: 6)
                        }

                        SwooshOrbView(configuration: orbConfig)
                            .frame(width: orbSize, height: orbSize)
                            .scaleEffect(pulseScale)
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            voiceMode.toggle()
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showChatBubble.toggle()
                        }
                    }

                    // State label
                    if voiceMode.isActive {
                        Text(stateLabel)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: voiceMode.isActive)
                .animation(.easeInOut(duration: 0.2), value: voiceMode.isListening)
                .animation(.easeInOut(duration: 0.2), value: voiceMode.isSpeaking)

                // ── Live transcript bubble ───────────────────────
                if voiceMode.isListening && !voiceMode.shell.speech.transcript.isEmpty {
                    transcriptBubble
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // ── Inline text chat bubble ──────────────────────
                if showChatBubble {
                    chatBubbleView
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .offset(x: 80, y: -60)
                }
            }
            .position(
                x: position.x + dragOffset.width,
                y: (position.y == 0 ? geo.size.height - 60 : position.y) + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        position.x += value.translation.width
                        position.y = (position.y == 0 ? geo.size.height - 60 : position.y) + value.translation.height
                        dragOffset = .zero
                    }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                    pulseScale = hovering ? 1.1 : 1.0
                }
            }
            .onAppear {
                if position.y == 0 {
                    position.y = geo.size.height - 60
                }
            }
            // Pulse the orb with audio level when listening
            .onChange(of: voiceMode.shell.speech.audioLevel) { _, level in
                let scale = 1.0 + CGFloat(level) * 0.15
                withAnimation(.easeOut(duration: 0.08)) {
                    pulseScale = isHovered ? max(1.1, scale) : scale
                }
            }
        }
        .allowsHitTesting(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Transcript bubble
    // ─────────────────────────────────────────────────────────────────

    private var transcriptBubble: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 5, height: 5)
                .shadow(color: .green.opacity(0.7), radius: 2)

            Text(voiceMode.shell.speech.transcript)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.green.opacity(0.3), lineWidth: 0.5)
                )
        )
        .offset(x: 80, y: -10)
        .frame(maxWidth: 240, alignment: .leading)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Inline chat bubble
    // ─────────────────────────────────────────────────────────────────

    private var chatBubbleView: some View {
        VStack(spacing: 8) {
            // Recent messages (last 3)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(voiceMode.shell.messages.suffix(5)) { msg in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(msg.role == .user ? Color.cyan.opacity(0.6) : Color.purple.opacity(0.6))
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
                            Text(msg.text)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(4)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)

            // Input field
            HStack(spacing: 6) {
                TextField("Ask agent…", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .onSubmit {
                        submitChat()
                    }

                Button {
                    submitChat()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.cyan.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
    }

    private func submitChat() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        voiceMode.shell.input = text
        chatInput = ""
        Task {
            await voiceMode.submitAndMaybeSpeak()
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - State label
    // ─────────────────────────────────────────────────────────────────

    private var stateLabel: String {
        if voiceMode.shell.isAwaitingResponse { return "Thinking…" }
        if voiceMode.isListening { return "Listening…" }
        if voiceMode.isSpeaking { return "Speaking…" }
        return "Ready"
    }
}

#endif
