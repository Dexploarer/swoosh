// SwooshEmbeddings/EmbeddingProviding.swift
// Version: 0.9R
//
// Local-first text embeddings. Apple's NaturalLanguage framework provides
// free, on-device sentence/word embeddings on macOS 13+/iOS 16+ — fine
// for routing, dedup, similarity, and small RAG. For higher fidelity the
// router falls back to a cloud OpenAI-compatible embeddings endpoint.

import Foundation

public protocol EmbeddingProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    /// Vector dimension. Used by the caller to size storage.
    func dimension() async -> Int
    /// Embed a single string.
    func embed(_ text: String) async throws -> [Float]
    /// Embed multiple strings — default impl loops sequentially.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

public extension EmbeddingProviding {
    func embed(_ texts: [String]) async throws -> [[Float]] {
        var out: [[Float]] = []
        out.reserveCapacity(texts.count)
        for t in texts {
            // `try await embed(t)` is the awaited call; `append` itself
            // is synchronous. The prior form parsed as `try await
            // out.append(...)` which is meaningless for a sync method.
            let vector = try await embed(t)
            out.append(vector)
        }
        return out
    }
}

public enum EmbeddingProviderError: Error, CustomStringConvertible, Sendable {
    case unsupportedPlatform
    case languageNotSupported(String)
    case modelUnavailable(String)
    case requestFailed(String)
    case missingAPIKey(String)

    public var description: String {
        switch self {
        case .unsupportedPlatform:
            return "Embeddings unavailable on this platform."
        case .languageNotSupported(let l):
            return "Embedding language \(l) is not supported by this provider."
        case .modelUnavailable(let m):
            return "Embedding model \(m) is not available locally."
        case .requestFailed(let m):
            return "Embedding request failed: \(m)"
        case .missingAPIKey(let p):
            return "Missing API key for \(p)."
        }
    }
}
