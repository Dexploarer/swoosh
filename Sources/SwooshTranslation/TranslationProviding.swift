// SwooshTranslation/TranslationProviding.swift
// Version: 0.9R
//
// Local-first translation backed by Apple's Translation framework
// (macOS 15+/iOS 18+). Cloud fallback when the system has not downloaded
// the requested language pair, or when the pair is unsupported.

import Foundation

public protocol TranslationProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    /// BCP-47 language pairs this provider supports. Empty == any-to-any.
    func supportedLanguagePairs() async -> [TranslationLanguagePair]
    func translate(_ text: String, from source: String?, to target: String) async throws -> String
}

public struct TranslationLanguagePair: Codable, Sendable, Hashable {
    public let source: String
    public let target: String
    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public enum TranslationProviderError: Error, CustomStringConvertible, Sendable {
    case unsupportedPlatform
    case unsupportedOSVersion
    case unsupportedLanguagePair(source: String?, target: String)
    case requestFailed(String)
    case missingAPIKey(String)

    public var description: String {
        switch self {
        case .unsupportedPlatform:
            return "Translation is unavailable on this platform."
        case .unsupportedOSVersion:
            return "Apple Translation requires macOS 15 / iOS 18 or newer."
        case .unsupportedLanguagePair(let s, let t):
            return "Language pair \(s ?? "auto")→\(t) is not supported."
        case .requestFailed(let m):
            return "Translation request failed: \(m)"
        case .missingAPIKey(let p):
            return "Missing API key for \(p)."
        }
    }
}
