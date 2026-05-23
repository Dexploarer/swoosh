// SwooshCapabilities/CapabilityRouter.swift
// Version: 0.9R
//
// Unified router for the six "new modalities" Swoosh shipped post-LLM:
//   • Vision (OCR, depth, foreground, document recognition, faces)
//   • Translation (Apple Translation + cloud fallback)
//   • Embeddings (Apple NaturalLanguage + cloud fallback)
//   • Image generation (Apple Image Playground + cloud fallback)
//   • Video generation (FAL.ai — Veo 3, Kling, Hunyuan, Luma)
//   • 3D generation (FAL.ai — Tripo3D, Trellis, TripoSR, Hunyuan3D)
//
// Pattern mirrors `VoiceRouter` in `SwooshVoiceProviders`: a `@MainActor`
// `@Observable` that reads UserDefaults for the current choice and
// instantiates the matching provider on demand. Swap providers by
// flipping a UserDefaults key from Settings — no app restart needed.
//
// API keys are read hot from Keychain via `KeychainAPIKeyProvider.for(_:)`
// each time a cloud provider is constructed. Writing or rotating a key
// in Keychain takes effect on the next `activeXProvider()` call — no
// app restart, no router reconfiguration. The same Keychain entries are
// shared with the voice picker (service `ai.swoosh.secrets`, account
// `ai.swoosh.<providerID>`), so one OpenAI key unlocks every OpenAI-backed
// surface.

import Foundation
import SwooshSecrets
import SwooshVision
import SwooshTranslation
import SwooshEmbeddings
import SwooshImageGen

@MainActor
@Observable
@preconcurrency
public final class CapabilityRouter {

    public static let shared = CapabilityRouter()

    public init() {}

    // MARK: - Keychain provider IDs

    /// Provider IDs used as Keychain accounts (`ai.swoosh.<id>` under
    /// service `ai.swoosh.secrets`). Shared with the voice picker.
    public enum KeychainProviderID {
        public static let openAI = "openai"
        public static let fal    = "fal"
    }

    /// True when the user has stored an OpenAI key in Keychain. Drives
    /// "configure your key" UI affordances for cloud choices.
    public var isOpenAIConfigured: Bool {
        KeychainAPIKeyProvider.isConfigured(providerID: KeychainProviderID.openAI)
    }

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
            return OpenAITranslationProvider(
                apiKey: KeychainAPIKeyProvider.for(KeychainProviderID.openAI)
            )
        case .routerLocalFirst:
            let cloud: (any TranslationProviding) = OpenAITranslationProvider(
                apiKey: KeychainAPIKeyProvider.for(KeychainProviderID.openAI)
            )
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
            return LocalOpenAICompatibleEmbeddingProvider(
                config: currentLocalEmbeddingChoice.config
            )
        case .openAI:
            return OpenAIEmbeddingProvider(
                apiKey: KeychainAPIKeyProvider.for(KeychainProviderID.openAI)
            )
        case .routerLocalFirst:
            let cloud: (any EmbeddingProviding) = OpenAIEmbeddingProvider(
                apiKey: KeychainAPIKeyProvider.for(KeychainProviderID.openAI)
            )
            return EmbeddingRouter(local: AppleNLEmbeddingProvider(), cloud: cloud)
        }
    }

    // MARK: - Local embedding preset

    /// Named on-device embedding backends. Used when `currentEmbeddingChoice`
    /// is `.localOpenAICompatible` to pick which local server + model to call.
    public enum LocalEmbeddingChoice: String, Sendable, CaseIterable, Identifiable {
        case ollamaNomicEmbed = "ollama-nomic-embed"
        case ollamaMxbaiEmbed = "ollama-mxbai-embed"
        case ollamaBGEM3      = "ollama-bge-m3"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .ollamaNomicEmbed: return "Ollama · nomic-embed-text (768-dim)"
            case .ollamaMxbaiEmbed: return "Ollama · mxbai-embed-large (1024-dim)"
            case .ollamaBGEM3:      return "Ollama · bge-m3 (1024-dim, multilingual)"
            }
        }

        public var config: LocalOpenAICompatibleEmbeddingProvider.Config {
            switch self {
            case .ollamaNomicEmbed: return .ollamaNomicEmbed
            case .ollamaMxbaiEmbed: return .ollamaMxbaiEmbed
            case .ollamaBGEM3:      return .ollamaBGEM3
            }
        }
    }

    public var currentLocalEmbeddingChoice: LocalEmbeddingChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: "swoosh.capabilities.localEmbedding") ?? "ollama-nomic-embed"
            return LocalEmbeddingChoice(rawValue: raw) ?? .ollamaNomicEmbed
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "swoosh.capabilities.localEmbedding") }
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
            return OpenAIImageProvider(
                apiKey: KeychainAPIKeyProvider.for(KeychainProviderID.openAI)
            )
        case .routerLocalFirst:
            let cloud: (any ImageGenProviding) = OpenAIImageProvider(
                apiKey: KeychainAPIKeyProvider.for(KeychainProviderID.openAI)
            )
            return ImageGenRouter(local: ImagePlaygroundProvider(), cloud: cloud)
        }
    }
}
