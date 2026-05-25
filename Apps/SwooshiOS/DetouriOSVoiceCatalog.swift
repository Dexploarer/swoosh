// DetouriOSVoiceCatalog.swift — native iOS speech voice inventory (0.5A)

import AVFoundation
import Foundation

struct DetouriOSVoice: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let quality: Int
    let isPersonalVoice: Bool
    let isNoveltyVoice: Bool

    var qualityLabel: String {
        let lowercasedID = id.lowercased()
        if isPersonalVoice {
            return "Personal Voice"
        }
        if isNoveltyVoice {
            return "Novelty"
        }
        if quality >= 3 || lowercasedID.contains("premium") {
            return "Premium"
        }
        if quality >= 2 || lowercasedID.contains("enhanced") {
            return "Enhanced"
        }
        if lowercasedID.contains("compact") || lowercasedID.contains("super-compact") {
            return "Compact"
        }
        return "System"
    }

    var isBestSystemVoice: Bool {
        let lowercasedID = id.lowercased()
        return isPersonalVoice
            || quality >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue
            || lowercasedID.contains("premium")
            || lowercasedID.contains("enhanced")
    }

    func menuTitle(isRecommended: Bool) -> String {
        var parts = [name, language, qualityLabel]
        if isRecommended {
            parts.append("Recommended")
        }
        return parts.joined(separator: " · ")
    }
}

enum DetouriOSVoiceCatalog {
    static func voices(languagePrefix: String = "en") -> [DetouriOSVoice] {
        rankedVoices(
            AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix(languagePrefix) }
                .filter { isSelectable($0) }
        )
        .map {
            let traits = $0.voiceTraits
            return DetouriOSVoice(
                id: $0.identifier,
                name: $0.name,
                language: $0.language,
                quality: $0.quality.rawValue,
                isPersonalVoice: traits.contains(.isPersonalVoice),
                isNoveltyVoice: traits.contains(.isNoveltyVoice)
            )
        }
    }

    static func defaultVoiceIdentifier() -> String? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = voices.filter { $0.language.hasPrefix("en") }
        return rankedVoices(englishVoices).first(where: { isSelectable($0) })?.identifier
            ?? voices.first(where: { $0.language == "en-US" })?.identifier
            ?? voices.first(where: { $0.language.hasPrefix("en") })?.identifier
    }

    private static func rankedVoices(_ voices: [AVSpeechSynthesisVoice]) -> [AVSpeechSynthesisVoice] {
        voices.sorted { left, right in
            let leftScore = score(left)
            let rightScore = score(right)
            if leftScore != rightScore {
                return leftScore > rightScore
            }

            let languageOrder = left.language.localizedStandardCompare(right.language)
            if languageOrder != .orderedSame {
                return languageOrder == .orderedAscending
            }

            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        let identifier = voice.identifier.lowercased()
        let traits = voice.voiceTraits
        var score = 0

        if voice.language == preferredEnglishLanguage {
            score += 10_000
        } else if voice.language == "en-US" {
            score += 9_000
        } else if voice.language.hasPrefix("en") {
            score += 7_000
        }

        score += voice.quality.rawValue * 1_000

        if identifier.contains("premium") {
            score += 3_000
        }
        if identifier.contains("enhanced") {
            score += 2_000
        }
        if identifier.contains("compact") {
            score -= 2_000
        }
        if identifier.contains("super-compact") {
            score -= 3_000
        }
        if identifier.contains("eloquence") {
            score -= 4_000
        }
        if traits.contains(.isPersonalVoice) {
            score += 4_000
        }
        if traits.contains(.isNoveltyVoice) {
            score -= 20_000
        }

        return score
    }

    private static func isSelectable(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.voiceTraits.contains(.isNoveltyVoice)
    }

    private static var preferredEnglishLanguage: String {
        let currentIdentifier = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        guard currentIdentifier.hasPrefix("en-") else {
            return "en-US"
        }
        return currentIdentifier
    }
}
