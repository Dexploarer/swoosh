// SwooshCapabilities/CapabilityRouter.swift
// Version: 0.9R
//
// Unified router for the four "new modalities" Swoosh shipped post-LLM:
//   • Vision (OCR, depth, foreground, document recognition, faces)
//   • Translation (Apple Translation + cloud fallback)
//   • Embeddings (Apple NaturalLanguage + cloud fallback)
//   • Image generation (Apple Image Playground + cloud fallback)
//
// Pattern mirrors `VoiceRouter` in `SwooshVoiceProviders`: a `@MainActor`
// `@Observable` that reads UserDefaults for the current choice and
// instantiates the matching provider on demand. Swap providers by
// flipping a UserDefaults key from Settings — no app restart needed.

import Foundation
import OSLog
import SwooshVision
import SwooshTranslation
import SwooshEmbeddings
import SwooshImageGen

private let logger = Logger(subsystem: "ai.swoosh.capabilities", category: "CapabilityRouter")

@MainActor
@Observable
public final class CapabilityRouter {

    public static let shared = CapabilityRouter()

    /// Optional injection point for cloud fallbacks. Set by the app on
    /// startup if cloud keys are configured. When nil, only the local
    /// path is attempted.
    public var openAIAPIKeyProvider: (@Sendable () async throws -> String)?

    /// FAL.ai key for video + 3D generation. Same shape as
    /// `openAIAPIKeyProvider` — closure-based so the router doesn't
    /// reach into Keychain directly.
    public var falAPIKeyProvider: (@Sendable () async throws -> String)?

    /// Optional URL override for the larger local embedding endpoint
    /// (Ollama default). When nil, the Ollama-default Nomic Embed
    /// config is used.
    public var localEmbeddingConfig: LocalOpenAICompatibleEmbeddingProvider.Config?

    public init() {}

    // MARK: - Vision

    public enum VisionChoice: String, Sendable, CaseIterable, Identifiable {
        case appleVision = "apple-vision"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .appleVision: return "Apple Vision (on-device)"
            }
        }
        public var isLocal: Bool { true }
    }

    public var currentVisionChoice: VisionChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.vision") ?? "apple-vision"
            return VisionChoice(rawValue: raw) ?? .appleVision
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.vision") }
    }

    public func activeVisionProvider() -> any VisionProviding {
        switch currentVisionChoice {
        case .appleVision: return AppleVisionProvider()
        }
    }

    // MARK: - Translation

    public enum TranslationChoice: String, Sendable, CaseIterable, Identifiable {
        case appleTranslation = "apple-translation"
        case openAI           = "openai-translation"
        case routerLocalFirst = "router-local-first"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .appleTranslation: return "Apple Translation (on-device)"
            case .openAI:           return "OpenAI (cloud)"
            case .routerLocalFirst: return "Auto — local first, cloud fallback"
            }
        }
        public var isLocal: Bool {
            switch self {
            case .appleTranslation: return true
            case .openAI:           return false
            case .routerLocalFirst: return true
            }
        }
    }

    public var currentTranslationChoice: TranslationChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.translation") ?? "router-local-first"
            return TranslationChoice(rawValue: raw) ?? .routerLocalFirst
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.translation") }
    }

    public func activeTranslationProvider() -> any TranslationProviding {
        switch currentTranslationChoice {
        case .appleTranslation:
            return AppleTranslationProvider()
        case .openAI:
            guard let provider = openAIAPIKeyProvider else {
                logger.warning("Translation choice .openAI selected but no API key provider configured — falling back to AppleTranslationProvider. Set an OpenAI key in Settings or change the choice.")
                return AppleTranslationProvider()
            }
            return OpenAITranslationProvider(apiKey: provider)
        case .routerLocalFirst:
            let cloud: (any TranslationProviding)? = openAIAPIKeyProvider.map {
                OpenAITranslationProvider(apiKey: $0)
            }
            return TranslationRouter(local: AppleTranslationProvider(), cloud: cloud)
        }
    }

    // MARK: - Embeddings

    public enum EmbeddingChoice: String, Sendable, CaseIterable, Identifiable {
        case appleNL              = "apple-nl"
        case localOpenAICompatible = "local-openai-embed"
        case openAI               = "openai-embed"
        case routerLocalFirst     = "router-local-first"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .appleNL:               return "Apple NaturalLanguage (on-device, 256–512 dim)"
            case .localOpenAICompatible: return "Local OpenAI-compatible (Ollama / LM Studio)"
            case .openAI:                return "OpenAI Embeddings (cloud, 1536 dim)"
            case .routerLocalFirst:      return "Auto — local first, cloud fallback"
            }
        }
        public var isLocal: Bool {
            switch self {
            case .appleNL, .localOpenAICompatible, .routerLocalFirst: return true
            case .openAI:                                              return false
            }
        }
    }

    public var currentEmbeddingChoice: EmbeddingChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.embedding") ?? "apple-nl"
            return EmbeddingChoice(rawValue: raw) ?? .appleNL
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.embedding") }
    }

    public func activeEmbeddingProvider() -> any EmbeddingProviding {
        switch currentEmbeddingChoice {
        case .appleNL:
            return AppleNLEmbeddingProvider()
        case .localOpenAICompatible:
            let config = localEmbeddingConfig ?? .ollamaNomicEmbed
            return LocalOpenAICompatibleEmbeddingProvider(config: config)
        case .openAI:
            guard let provider = openAIAPIKeyProvider else { return AppleNLEmbeddingProvider() }
            return OpenAIEmbeddingProvider(apiKey: provider)
        case .routerLocalFirst:
            let cloud: (any EmbeddingProviding)? = openAIAPIKeyProvider.map {
                OpenAIEmbeddingProvider(apiKey: $0)
            }
            let localConfig = localEmbeddingConfig ?? .ollamaNomicEmbed
            let local: any EmbeddingProviding = (localEmbeddingConfig != nil)
                ? LocalOpenAICompatibleEmbeddingProvider(config: localConfig)
                : AppleNLEmbeddingProvider()
            return EmbeddingRouter(local: local, cloud: cloud)
        }
    }

    // MARK: - Image generation

    public enum ImageGenChoice: String, Sendable, CaseIterable, Identifiable {
        case imagePlayground  = "apple-image-playground"
        case openAI           = "openai-image"
        case routerLocalFirst = "router-local-first"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .imagePlayground:  return "Apple Image Playground (on-device)"
            case .openAI:           return "OpenAI Image (cloud)"
            case .routerLocalFirst: return "Auto — local first, cloud fallback"
            }
        }
        public var isLocal: Bool {
            switch self {
            case .imagePlayground:  return true
            case .openAI:           return false
            case .routerLocalFirst: return true
            }
        }
    }

    public var currentImageGenChoice: ImageGenChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.imageGen") ?? "router-local-first"
            return ImageGenChoice(rawValue: raw) ?? .routerLocalFirst
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.imageGen") }
    }

    public func activeImageGenProvider() -> any ImageGenProviding {
        switch currentImageGenChoice {
        case .imagePlayground:
            return ImagePlaygroundProvider()
        case .openAI:
            guard let provider = openAIAPIKeyProvider else { return ImagePlaygroundProvider() }
            return OpenAIImageProvider(apiKey: provider)
        case .routerLocalFirst:
            let cloud: (any ImageGenProviding)? = openAIAPIKeyProvider.map {
                OpenAIImageProvider(apiKey: $0)
            }
            return ImageGenRouter(local: ImagePlaygroundProvider(), cloud: cloud)
        }
    }
}
