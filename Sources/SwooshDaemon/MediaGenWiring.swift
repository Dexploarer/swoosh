// SwooshDaemon/MediaGenWiring.swift — 0.4A Media generation provider wiring
//
// Construct `MediaGenDependencies` for the daemon. Each provider is
// built only when its Keychain key is present (or, for the local
// image path, always). Firewall + audit injections come from the
// daemon's tool runtime so direct (non-registry) calls into the
// providers stay gated as defense-in-depth — the registry-mounted
// tool wrappers are the primary gate.

import Foundation
import SwooshTools
import SwooshSecrets
import SwooshImageGen
import SwooshMusic
import SwooshToolsets

enum MediaGenWiring {

    /// Build the media-gen dependency bundle from the daemon's tool
    /// runtime + the user's Keychain entries. Returns nil only when
    /// every modality is unconfigured, so `registerAll` can skip the
    /// registrar entirely.
    static func build(
        firewall: any Firewall,
        auditLog: any AuditLogging
    ) -> MediaGenDependencies? {
        let imageProvider = buildImage(firewall: firewall, auditLog: auditLog)
        let videoProvider = buildVideo(firewall: firewall, auditLog: auditLog)
        let threeDProvider = buildThreeD(firewall: firewall, auditLog: auditLog)
        let musicProvider = buildMusic(firewall: firewall, auditLog: auditLog)

        if imageProvider == nil
            && videoProvider == nil
            && threeDProvider == nil
            && musicProvider == nil {
            return nil
        }
        return MediaGenDependencies(
            imageProvider: imageProvider,
            videoProvider: videoProvider,
            threeDProvider: threeDProvider,
            musicProvider: musicProvider
        )
    }

    // MARK: - Image

    /// Local Image Playground is always available on supported Apple
    /// OSes — wrap it in the router with optional cloud fallback when
    /// the OpenAI key is present.
    private static func buildImage(
        firewall: any Firewall,
        auditLog: any AuditLogging
    ) -> (any ImageGenProviding)? {
        let local = ImagePlaygroundProvider(firewall: firewall, auditLog: auditLog)
        let cloud: (any ImageGenProviding)?
        if KeychainAPIKeyProvider.isConfigured(providerID: "openai") {
            cloud = OpenAIImageProvider(
                apiKey: KeychainAPIKeyProvider.for("openai"),
                firewall: firewall,
                auditLog: auditLog
            )
        } else {
            cloud = nil
        }
        return ImageGenRouter(local: local, cloud: cloud)
    }

    // MARK: - Video

    private static func buildVideo(
        firewall: any Firewall,
        auditLog: any AuditLogging
    ) -> (any VideoGenProviding)? {
        guard KeychainAPIKeyProvider.isConfigured(providerID: "fal") else { return nil }
        let client = FALClient(
            apiKey: KeychainAPIKeyProvider.for("fal"),
            firewall: firewall,
            auditLog: auditLog
        )
        return FALVideoProvider(client: client, firewall: firewall, auditLog: auditLog)
    }

    // MARK: - 3D

    private static func buildThreeD(
        firewall: any Firewall,
        auditLog: any AuditLogging
    ) -> (any ThreeDGenProviding)? {
        guard KeychainAPIKeyProvider.isConfigured(providerID: "fal") else { return nil }
        let client = FALClient(
            apiKey: KeychainAPIKeyProvider.for("fal"),
            firewall: firewall,
            auditLog: auditLog
        )
        return FALThreeDProvider(client: client, firewall: firewall, auditLog: auditLog)
    }

    // MARK: - Music

    /// Build a music router from whichever provider keys are present.
    /// Suno → ElevenLabs → Stable Audio in priority order. Returns nil
    /// when none are configured.
    private static func buildMusic(
        firewall: any Firewall,
        auditLog: any AuditLogging
    ) -> (any MusicProviding)? {
        var providers: [any MusicProviding] = []
        if KeychainAPIKeyProvider.isConfigured(providerID: "suno") {
            providers.append(SunoMusicProvider(
                apiKeyProvider: KeychainAPIKeyProvider.for("suno"),
                firewall: firewall,
                auditLog: auditLog
            ))
        }
        if KeychainAPIKeyProvider.isConfigured(providerID: "elevenlabs") {
            providers.append(ElevenLabsMusicProvider(
                apiKeyProvider: KeychainAPIKeyProvider.for("elevenlabs"),
                firewall: firewall,
                auditLog: auditLog
            ))
        }
        if KeychainAPIKeyProvider.isConfigured(providerID: "stability") {
            providers.append(StableAudioProvider(
                apiKeyProvider: KeychainAPIKeyProvider.for("stability"),
                firewall: firewall,
                auditLog: auditLog
            ))
        }
        guard !providers.isEmpty else { return nil }
        return MusicRouter(providers: providers)
    }
}
