// Apps/SwooshiOS/AudioLevelSource.swift — 0.9R Unified audio-level publisher
//
// Pulls a single normalized [0, 1] amplitude from whichever source is
// active right now. Two contributors today:
//
//   • Mic capture: `AgentShellModel.speech` (`SpeechCapture` is already
//     `@Observable` and exposes a `level: Float` that we forward.
//   • Playback: AVAudioPlayer's `averagePower(forChannel: 0)` when
//     `TTSPlayback` has an active player. Polled at ~30 Hz.
//
// The level drives both the liquid sphere's visual deformation and the
// `VoiceHapticsCoordinator`'s pattern parameters, so they stay in sync
// without each component sampling audio independently.

import Foundation
import AVFoundation
import Observation
import SwooshUI
import SwooshVoiceProviders

@MainActor
@Observable
final class AudioLevelSource {

    /// Live amplitude in [0, 1]. Smoothed via simple low-pass so the
    /// sphere doesn't jitter between samples.
    private(set) var level: Float = 0.0

    /// True while at least one source is producing audio (mic listening,
    /// TTS playback). Drives sphere visibility.
    private(set) var isActive: Bool = false

    private weak var shell: AgentShellModel?
    private weak var playback: TTSPlayback?

    private var pollTask: Task<Void, Never>?

    /// Attach to the shell (for mic level) and TTS playback (for output
    /// level). Calling repeatedly with new instances reattaches.
    func bind(shell: AgentShellModel, playback: TTSPlayback) {
        self.shell = shell
        self.playback = playback
        startPolling()
    }

    func detach() {
        pollTask?.cancel()
        pollTask = nil
        shell = nil
        playback = nil
        level = 0
        isActive = false
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30 Hz
            }
        }
    }

    private func sample() {
        var newLevel: Float = 0
        var anyActive = false

        // Mic
        if let shell, shell.voice != .idle {
            // SpeechCapture already normalises RMS to [0, 1].
            newLevel = max(newLevel, shell.speech.audioLevel)
            anyActive = true
        }

        // Playback
        if let playback, playback.isPlaying, let avg = playback.averagePowerDB() {
            // averagePower is in dB (negative). Map -50..0 → 0..1.
            let normalized = max(0, min(1, (avg + 50) / 50))
            newLevel = max(newLevel, normalized)
            anyActive = true
        }

        // Single-pole low-pass smooth so the sphere doesn't jitter.
        level = level * 0.55 + newLevel * 0.45
        isActive = anyActive
    }
}
