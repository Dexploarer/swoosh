// SwooshImageGen/ImageGenRouter.swift
// Version: 0.9R
//
// Local-first router. Apple Image Playground when the OS supports it,
// otherwise fall through to the injected cloud provider. The router
// itself is `ImageGenProviding` so callers see one interface.

import Foundation

public actor ImageGenRouter: ImageGenProviding {
    private let local: any ImageGenProviding
    private let cloud: (any ImageGenProviding)?

    public init(local: any ImageGenProviding = ImagePlaygroundProvider(), cloud: (any ImageGenProviding)? = nil) {
        self.local = local
        self.cloud = cloud
    }

    public nonisolated var id: String { "image-gen-router" }
    public nonisolated var displayName: String { "Image gen · \(local.displayName) + cloud fallback" }
    /// True only when no cloud fallback is configured — once a cloud
    /// provider is wired the router may serve from it on any given turn,
    /// so `isLocal` would be misleading. Callers wanting "local-only"
    /// behaviour should hold the `local` provider directly.
    public nonisolated var isLocal: Bool { cloud == nil }
    /// True when any underlying provider supports a custom size. `generate`
    /// will try `local` first and fall through to `cloud` if local can't
    /// honour the request — so as long as one of them can, we advertise it.
    public nonisolated var supportsCustomSize: Bool {
        local.supportsCustomSize || (cloud?.supportsCustomSize ?? false)
    }

    public func supportedStyles() async -> [ImageGenStyle] {
        // Advertise the union so callers see every style at least one
        // provider supports — `generate(_:)` already prefers `local`
        // and falls through to `cloud` on failure.
        let localStyles = await local.supportedStyles()
        guard let cloud else { return localStyles }
        let cloudStyles = await cloud.supportedStyles()
        var seen = Set<String>()
        var merged: [ImageGenStyle] = []
        for style in localStyles + cloudStyles where seen.insert(style.id).inserted {
            merged.append(style)
        }
        return merged
    }

    public func generate(_ request: ImageGenRequest) async throws -> ImageGenResult {
        do {
            return try await local.generate(request)
        } catch {
            guard let cloud else { throw error }
            return try await cloud.generate(request)
        }
    }
}

public enum SwooshImageGen {
    public static func defaultProvider(cloud: (any ImageGenProviding)? = nil) -> any ImageGenProviding {
        ImageGenRouter(local: ImagePlaygroundProvider(), cloud: cloud)
    }
}
