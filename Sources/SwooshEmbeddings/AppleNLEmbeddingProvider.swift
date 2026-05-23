// SwooshEmbeddings/AppleNLEmbeddingProvider.swift
// Version: 0.9R
//
// Apple NaturalLanguage word/sentence embeddings. Free, on-device, no
// downloads. Returns 256–512 dim vectors depending on language model.
//
// For sentences, we average word vectors when the system sentence
// embedding is unavailable for the detected language.

import Foundation

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public actor AppleNLEmbeddingProvider: EmbeddingProviding {

    private let language: String

    /// `language` is a BCP-47 code; `.english` ("en") is a reasonable default
    /// since Apple's English embedding is the most widely covered.
    public init(language: String = "en") {
        self.language = language
    }

    public nonisolated var id: String { "apple-nl" }
    public nonisolated var displayName: String { "Apple NaturalLanguage (on-device)" }
    public nonisolated var isLocal: Bool { true }

    public func dimension() async -> Int {
        #if canImport(NaturalLanguage)
        let nlLang = NLLanguage(rawValue: language)
        if let sentence = NLEmbedding.sentenceEmbedding(for: nlLang) { return sentence.dimension }
        if let word = NLEmbedding.wordEmbedding(for: nlLang) { return word.dimension }
        return 0
        #else
        return 0
        #endif
    }

    public func embed(_ text: String) async throws -> [Float] {
        #if canImport(NaturalLanguage)
        let nlLang = NLLanguage(rawValue: language)
        if let sentence = NLEmbedding.sentenceEmbedding(for: nlLang),
           let vec = sentence.vector(for: text) {
            return vec.map { Float($0) }
        }
        guard let word = NLEmbedding.wordEmbedding(for: nlLang) else {
            throw EmbeddingProviderError.languageNotSupported(language)
        }
        let tokens = tokenize(text: text)
        let vectors = tokens.compactMap { word.vector(for: $0) }
        guard !vectors.isEmpty else {
            throw EmbeddingProviderError.requestFailed("No embeddable tokens in input")
        }
        var sum: [Double] = Array(repeating: 0, count: word.dimension)
        for vec in vectors {
            for i in 0..<sum.count { sum[i] += vec[i] }
        }
        let inv = 1.0 / Double(vectors.count)
        return sum.map { Float($0 * inv) }
        #else
        throw EmbeddingProviderError.unsupportedPlatform
        #endif
    }

    #if canImport(NaturalLanguage)
    private func tokenize(text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]).lowercased())
            return true
        }
        return tokens
    }
    #endif
}
