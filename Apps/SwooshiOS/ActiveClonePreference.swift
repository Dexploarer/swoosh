// Apps/SwooshiOS/ActiveClonePreference.swift — 0.9R Selected clone for TTS
//
// One-key UserDefaults wrapper for the user's currently-selected voice
// clone. Read by AgentRoot when it routes a PocketTTS TTS turn so the
// agent answers in the chosen voice. Nil → use the model's default voice.

import Foundation

enum ActiveClonePreference {
    private static let key = "swoosh.voice.activeCloneID"

    /// Slug ID of the currently selected clone (or nil for "default").
    static var current: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
