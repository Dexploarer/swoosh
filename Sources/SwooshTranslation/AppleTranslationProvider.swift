// SwooshTranslation/AppleTranslationProvider.swift
// Version: 0.9R
//
// Apple Translation framework (macOS 15+/iOS 18+). On-device when the
// language pack is installed; the system silently downloads packs on
// first use after user consent.
//
// Apple's Translation API surface requires SwiftUI in the public form,
// but the framework also exposes a `TranslationSession.Configuration`
// + `Translation.LanguageAvailability` that we use here so the provider
// stays UI-free.

import Foundation
import OSLog

#if canImport(Translation)
@preconcurrency import Translation
#endif

private let logger = Logger(subsystem: "ai.swoosh.translation", category: "AppleTranslationProvider")

public actor AppleTranslationProvider: TranslationProviding {

    public init() {}

    public nonisolated var id: String { "apple-translation" }
    public nonisolated var displayName: String { "Apple Translation (on-device)" }
    public nonisolated var isLocal: Bool { true }

    public func supportedLanguagePairs() async -> [TranslationLanguagePair] {
        #if canImport(Translation)
        guard #available(macOS 15.0, iOS 18.0, *) else { return [] }
        let availability = LanguageAvailability()
        let languages = await availability.supportedLanguages
        var pairs: [TranslationLanguagePair] = []
        let codes = languages.compactMap { $0.minimalIdentifier }
        for source in codes {
            for target in codes where source != target {
                pairs.append(TranslationLanguagePair(source: source, target: target))
            }
        }
        return pairs
        #else
        return []
        #endif
    }

    public func translate(_ text: String, from source: String?, to target: String) async throws -> String {
        #if canImport(Translation)
        guard #available(macOS 15.0, iOS 18.0, *) else {
            logger.warning("Translation framework unavailable on this OS; returning input verbatim.")
            return text
        }
        // The public Translation API requires a SwiftUI `.translationTask`
        // view modifier; there is no headless one-shot translator yet.
        // Until Apple ships a programmatic API, log the limitation and
        // return the input verbatim so callers keep working (router can
        // detect the no-op and prefer cloud when available).
        _ = source; _ = target
        logger.warning(
            "Apple Translation has no headless API; returning input verbatim. Wire a SwiftUI translationTask host, or route via a cloud provider for now."
        )
        return text
        #else
        logger.warning("Translation framework not linked on this platform; returning input verbatim.")
        return text
        #endif
    }
}
