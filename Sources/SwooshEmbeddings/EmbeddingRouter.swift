// SwooshEmbeddings/EmbeddingRouter.swift
// Version: 0.9S
//
// Local-first router. Apple NL first, cloud only when the user opted
// in (a cloud provider was injected) AND the local provider returned no
// embedding (rare).
//
// 0.9S: removed the orphan `enum SwooshEmbeddings { defaultProvider }`
// namespace — its name collided with the module name (`import
// SwooshEmbeddings` then `SwooshEmbeddings.defaultProvider(...)` is
// ambiguous in Swift) and it had zero callers. Construct
// `EmbeddingRouter` directly; the AppleNL default lives on the init's
// `local:` parameter.

import Foundation

public actor EmbeddingRouter: EmbeddingProviding {
    private let local: any EmbeddingProviding
    private let cloud: (any EmbeddingProviding)?

    public init(local: any EmbeddingProviding = AppleNLEmbeddingProvider(), cloud: (any EmbeddingProviding)? = nil) {
        self.local = local
        self.cloud = cloud
    }

    public nonisolated var id: String { "embedding-router" }
    public nonisolated var displayName: String { "Embeddings (router)" }
    public nonisolated var isLocal: Bool { true }

    public func dimension() async -> Int { await local.dimension() }

    public func embed(_ text: String) async throws -> [Float] {
        do {
            return try await local.embed(text)
        } catch {
            guard let cloud else { throw error }
            return try await cloud.embed(text)
        }
    }
}
