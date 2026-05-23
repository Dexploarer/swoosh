// SwooshTranslation/TranslationRouter.swift
// Version: 0.9R
//
// Local-first router: try Apple Translation, fall back to cloud when
// the pair is unsupported or the framework is unavailable.

import Foundation

public actor TranslationRouter: TranslationProviding {
    private let local: any TranslationProviding
    private let cloud: (any TranslationProviding)?

    public init(local: any TranslationProviding = AppleTranslationProvider(), cloud: (any TranslationProviding)? = nil) {
        self.local = local
        self.cloud = cloud
    }

    public nonisolated var id: String { "translation-router" }
    public nonisolated var displayName: String { "Translation (router)" }
    public nonisolated var isLocal: Bool { true }

    public func supportedLanguagePairs() async -> [TranslationLanguagePair] {
        await local.supportedLanguagePairs()
    }

    public func translate(_ text: String, from source: String?, to target: String) async throws -> String {
        do {
            return try await local.translate(text, from: source, to: target)
        } catch {
            guard let cloud else { throw error }
            return try await cloud.translate(text, from: source, to: target)
        }
    }
}

public enum SwooshTranslation {
    public static func defaultProvider(cloud: (any TranslationProviding)? = nil) -> any TranslationProviding {
        TranslationRouter(local: AppleTranslationProvider(), cloud: cloud)
    }
}
