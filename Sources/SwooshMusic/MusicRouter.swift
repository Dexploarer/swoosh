// SwooshMusic/MusicRouter.swift — 0.9S Music-gen provider router
//
// Cloud-only today. Picks the first non-nil provider in priority order;
// no local fallback (no on-device music model is shipping in Swoosh yet).
// Mirrors the shape of `ImageGenRouter` so the tool wrapper sees a
// single `MusicProviding` regardless of which backend is configured.
//
// Gating happens at the leaves — each provider gates its own work
// against `.musicGenerate` when a firewall is injected. The router
// adds no enforcement on top; the registry-mounted `GenerateMusicTool`
// is the primary permission gate for agent calls.

import Foundation
import SwooshTools

public actor MusicRouter: MusicProviding {
    private let providers: [any MusicProviding]

    public init(providers: [any MusicProviding]) {
        self.providers = providers
    }

    public nonisolated var id: String { "music-router" }
    public nonisolated var displayName: String { "Music Router" }
    public nonisolated var availableModels: [MusicModel] {
        var seen = Set<String>()
        var out: [MusicModel] = []
        for provider in providers {
            for model in provider.availableModels where seen.insert(model.id).inserted {
                out.append(model)
            }
        }
        return out
    }

    public func generate(_ request: MusicRequest) async throws -> MusicJob {
        guard let first = providers.first else {
            throw MusicError.requestFailed("no music providers configured")
        }
        var lastError: Error?
        for provider in providers {
            do {
                return try await provider.generate(request)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? MusicError.requestFailed("\(first.displayName) generate failed")
    }
}

public enum SwooshMusic {
    /// Construct the default router from the first provider whose API
    /// key is available. Callers wire `apiKeyProvider` per provider —
    /// providers that throw on key lookup are skipped at request time.
    public static func defaultProvider(
        providers: [any MusicProviding]
    ) -> any MusicProviding {
        MusicRouter(providers: providers)
    }
}
