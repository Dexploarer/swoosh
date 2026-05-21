// SwooshVoiceProviders/Logging.swift — 0.9R os.Logger subsystems
//
// Single subsystem (`ai.swoosh`) with per-module categories so console
// filtering is easy:
//
//   xcrun simctl spawn booted log stream --predicate 'subsystem == "ai.swoosh"'
//
// Categories:
//   • tts       — provider HTTP + synthesis
//   • streaming — AVAudioEngine player state transitions
//   • whisper   — STT engine load + transcribe
//   • music     — music-gen job lifecycle
//   • keychain  — secret read/write (no values)

import Foundation
import os

internal enum Logger {
    static let tts       = os.Logger(subsystem: "ai.swoosh", category: "tts")
    static let streaming = os.Logger(subsystem: "ai.swoosh", category: "streaming")
    static let whisper   = os.Logger(subsystem: "ai.swoosh", category: "whisper")
    static let music     = os.Logger(subsystem: "ai.swoosh", category: "music")
    static let keychain  = os.Logger(subsystem: "ai.swoosh", category: "keychain")
}
