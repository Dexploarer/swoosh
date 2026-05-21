// SwooshUI/Voice/VoiceMode.swift — 0.9R Voice mode orchestrator
//
// Top-level coordinator for the always-on voice experience. When the
// user enters voice mode, the bottom pill appears, the mic is hot, and
// agent responses are spoken back if TTS is enabled.
//
// Three subsystems wire in independently — any combination works:
//
//   STT (SpeechCapture) ──┐
//                          │
//                          ▼          ┌── speaks ─→ TTSEngine (optional)
//                    AgentShellModel ─┤
//                          │          └── renders ─→ DesktopOverlay (optional)
//                          │
//                          ▼
//                     surfaceHost ──→ generative UI on desktop
//
// "Voice mode on but no TTS engine attached" works → user dictates,
// reads replies. "Voice mode on but no overlay" works → response shows
// in the bottom pill instead of being projected to the desktop. "Voice
// mode off" works → mic is decorative, like before.

import Foundation
import Observation
import SwooshGenerativeUI

/// Where the agent's response is presented while voice mode is active.
public enum VoiceResponsePresentation: String, Sendable, CaseIterable {
    /// Agent reply renders inside the bottom voice pill itself.
    case pill
    /// Agent reply is projected onto the desktop overlay scene.
    case desktopOverlay
    /// Both.
    case both
}

@MainActor
@Observable
public final class VoiceMode {

    // ── Subsystem references ────────────────────────────────────────

    /// The shell the voice loop drives. Send + STT + surface host all
    /// already live here.
    public let shell: AgentShellModel

    /// Optional TTS. nil = voice mode runs without spoken replies.
    public var tts: TTSEngine?

    // ── User-toggleable flags ───────────────────────────────────────

    /// Master switch. When true, the bottom pill is visible and STT is
    /// either hot or hot-on-tap depending on `pushToTalk`.
    public var isActive: Bool = false

    /// When true, TTS speaks every agent reply (if a TTS engine is set).
    public var speakReplies: Bool = true

    /// When true, generative-UI surfaces emitted by the agent are pushed
    /// onto the desktop overlay scene as well as the in-pill panel.
    public var projectToDesktop: Bool = true

    /// Where to render agent replies (text, not UI surfaces).
    public var presentation: VoiceResponsePresentation = .pill

    /// Hold-to-talk vs always-on. Hold mode mirrors the macOS Dictation
    /// default; always-on is a hands-free flow that ends utterances on
    /// silence.
    public var pushToTalk: Bool = true

    // ── Read-only derived state ─────────────────────────────────────

    public var isListening: Bool { shell.voice == .listening }

    public var hasTTS: Bool { tts != nil }

    public var isSpeaking: Bool { tts?.isSpeaking ?? false }

    /// `true` when at least one downstream consumer (pill or overlay) will
    /// show the agent's text reply. Lets a smart caller skip enqueuing UI
    /// state when there's nowhere to display it.
    public var hasPresentation: Bool {
        // The pill is always present while voice mode is active, so the
        // answer is always yes — kept as a property so future variations
        // (e.g. headless voice agent) can short-circuit.
        isActive
    }

    // ── Lifecycle ────────────────────────────────────────────────────

    public init(shell: AgentShellModel, tts: TTSEngine? = nil) {
        self.shell = shell
        self.tts = tts
    }

    // ── Entry / exit ─────────────────────────────────────────────────

    /// Turn voice mode on. Posts the show-pill notification so the bottom
    /// pill scene mounts itself.
    public func start() {
        guard !isActive else { return }
        isActive = true
        NotificationCenter.default.post(name: .swooshShowVoicePillBottom, object: nil)
        if projectToDesktop {
            NotificationCenter.default.post(name: .swooshShowDesktopOverlay, object: nil)
        }
        if !pushToTalk {
            shell.startListening()
        }
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        shell.stopListening(commit: false)
        tts?.stop()
        NotificationCenter.default.post(name: .swooshHideVoicePillBottom, object: nil)
        NotificationCenter.default.post(name: .swooshHideDesktopOverlay, object: nil)
    }

    public func toggle() {
        if isActive { stop() } else { start() }
    }

    // ── Hold-to-talk ─────────────────────────────────────────────────

    public func pressMicDown() {
        guard isActive else { return }
        if pushToTalk { shell.startListening() }
    }

    public func releaseMic() {
        guard isActive, pushToTalk else { return }
        let captured = shell.speech.transcript
        shell.stopListening(commit: false)
        if !captured.isEmpty {
            shell.input = captured
            Task { await submitAndMaybeSpeak() }
        }
    }

    // ── Single-shot submit + speak (no microphone) ──────────────────

    /// Submit whatever's in `shell.input` and, if TTS is enabled, speak
    /// the agent's reply. Used by the "tap to send" affordance on the
    /// bottom pill — handy when the user has typed instead of spoken.
    public func submitAndMaybeSpeak() async {
        let priorCount = shell.messages.count
        await shell.submit()
        // The agent's reply is the last message appended by submit().
        guard shell.messages.count > priorCount,
              let reply = shell.messages.last,
              reply.role == .agent else { return }
        if speakReplies, let tts {
            tts.speak(reply.text)
        }
    }
}

// MARK: - Notification names

public extension Notification.Name {
    static let swooshShowVoicePillBottom = Notification.Name("ai.swoosh.showVoicePillBottom")
    static let swooshHideVoicePillBottom = Notification.Name("ai.swoosh.hideVoicePillBottom")
    static let swooshShowDesktopOverlay  = Notification.Name("ai.swoosh.showDesktopOverlay")
    static let swooshHideDesktopOverlay  = Notification.Name("ai.swoosh.hideDesktopOverlay")
}
