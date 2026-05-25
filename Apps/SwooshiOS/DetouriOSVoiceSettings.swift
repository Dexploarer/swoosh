// DetouriOSVoiceSettings.swift — app-wide voice selection (0.5A)

import Foundation

enum DetouriOSVoiceSettings {
    static let ttsEngineKey = "swoosh.voice.ttsEngine"
    static let kokoroVoiceIDKey = "swoosh.voice.kokoroVoiceID"
    static let localEngineID = "kokoro-local"
    static let defaultKokoroVoiceID = "af_heart"

    static var selectedEngineID: String {
        UserDefaults.standard.string(forKey: ttsEngineKey) ?? localEngineID
    }

    static var selectedKokoroVoiceID: String {
        let stored = UserDefaults.standard.string(forKey: kokoroVoiceIDKey)
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultKokoroVoiceID
        }
        return stored
    }

    static func useDefaultLocalVoice() {
        UserDefaults.standard.set(localEngineID, forKey: ttsEngineKey)
        UserDefaults.standard.set(defaultKokoroVoiceID, forKey: kokoroVoiceIDKey)
    }

}
