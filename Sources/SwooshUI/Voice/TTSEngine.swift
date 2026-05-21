// SwooshUI/Voice/TTSEngine.swift — 0.9R Text-to-speech engine
//
// AVSpeechSynthesizer wrapper. Speaks agent responses when voice mode is
// on and TTS is enabled. Independent — voice mode works fine without
// this (transcription-only); this works fine without voice mode (any
// caller can speak a string).
//
// Configuration is shallow on purpose. macOS ships a curated set of
// system voices; users pick one in System Settings → Accessibility →
// Spoken Content. We read that selection by default.

import Foundation
import AVFoundation

@MainActor
@Observable
public final class TTSEngine: NSObject {

    // MARK: - Published state

    /// True while the synthesizer is reading aloud.
    public private(set) var isSpeaking: Bool = false

    /// Current utterance text — exposed so a UI can show the user what's
    /// being read (useful for accessibility + debug).
    public private(set) var currentText: String?

    // MARK: - Configuration

    /// Voice identifier from `AVSpeechSynthesisVoice.identifier`. nil =
    /// system default. Set via `voice(named:)` for human-readable lookup.
    public var voiceIdentifier: String? = nil

    /// Speaking rate. AVSpeechUtterance default is ~0.5; useful range
    /// 0.4–0.6 for natural speech.
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// Pitch multiplier. 1.0 is neutral. Range 0.5–2.0.
    public var pitch: Float = 1.0

    /// Volume in [0,1].
    public var volume: Float = 1.0

    // MARK: - Engine

    private let synth: AVSpeechSynthesizer

    public override init() {
        self.synth = AVSpeechSynthesizer()
        super.init()
        synth.delegate = self
    }

    // MARK: - Speak

    /// Speak the supplied text. If the synth is already speaking, the new
    /// utterance is queued (AVSpeechSynthesizer handles this).
    public func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        currentText = text
        synth.speak(utterance)
    }

    /// Stop everything immediately. Empties the queue.
    public func stop() {
        synth.stopSpeaking(at: .immediate)
        currentText = nil
        isSpeaking = false
    }

    /// Pause the current utterance (resume with `resume()`).
    public func pause() { synth.pauseSpeaking(at: .immediate) }
    public func resume() { synth.continueSpeaking() }

    // MARK: - Voice picker helpers

    /// All voices available to the system, sorted by language.
    public func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { $0.language < $1.language }
    }

    /// Set the active voice by display name (e.g. "Samantha"). Falls back
    /// to system default if the name doesn't match anything.
    public func voice(named name: String) {
        if let v = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == name }) {
            voiceIdentifier = v.identifier
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSEngine: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentText = nil
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentText = nil
        }
    }
}
