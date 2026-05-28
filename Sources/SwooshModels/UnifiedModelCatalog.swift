// SwooshModels/UnifiedModelCatalog.swift - Canonical model defaults and registry - 0.9S

import Foundation

public enum ModelRuntimeKind: String, Codable, Sendable, CaseIterable {
    case router
    case codex
    case openAI
    case openRouter
    case detourCloud
    case localOpenAI
    case localMLX
    case localLiteRT
    case localFoundation
}

/// Content rating for model entries. NSFW models require explicit user
/// confirmation before they appear in the model picker or can be downloaded.
public enum ModelContentRating: String, Codable, Sendable, CaseIterable {
    case general     // Safe for all audiences
    case nsfw        // Adult / explicit content — requires confirmation gate
}

public struct UnifiedModelEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let modelID: String
    public let providerID: String
    public let displayName: String
    public let family: String
    public let runtime: ModelRuntimeKind
    public let contextWindow: Int?
    public let estimatedMemoryGB: Double?
    public let capabilities: Set<ModelCapability>
    public let roles: Set<ModelRole>
    public let supportsReasoningEffort: Bool
    public let blurb: String
    public let installCommands: [ModelSource: String]
    public let contentRating: ModelContentRating
    /// For LoRA adapters: the base model ID this adapter requires.
    public let baseModelID: String?

    public init(
        id: String,
        modelID: String,
        providerID: String,
        displayName: String,
        family: String,
        runtime: ModelRuntimeKind,
        contextWindow: Int? = nil,
        estimatedMemoryGB: Double? = nil,
        capabilities: Set<ModelCapability>,
        roles: Set<ModelRole>,
        supportsReasoningEffort: Bool = false,
        blurb: String,
        installCommands: [ModelSource: String] = [:],
        contentRating: ModelContentRating = .general,
        baseModelID: String? = nil
    ) {
        self.id = id
        self.modelID = modelID
        self.providerID = providerID
        self.displayName = displayName
        self.family = family
        self.runtime = runtime
        self.contextWindow = contextWindow
        self.estimatedMemoryGB = estimatedMemoryGB
        self.capabilities = capabilities
        self.roles = roles
        self.supportsReasoningEffort = supportsReasoningEffort
        self.blurb = blurb
        self.installCommands = installCommands
        self.contentRating = contentRating
        self.baseModelID = baseModelID
    }

    /// Whether this entry is a LoRA adapter (requires a base model).
    public var isLoRA: Bool { baseModelID != nil }

    /// Whether this entry requires NSFW confirmation before use.
    public var requiresNSFWConfirmation: Bool { contentRating == .nsfw }
}

public enum ModelDefaults {
    public static let routerProviderID = "router"
    public static let routerModelID = "auto"
    public static let defaultInteractiveModelID = "auto"

    public static let codexProviderID = "codex"
    public static let codexModelID = "auto"

    public static let openAIProviderID = "openai"
    // Aligned with detour/eliza/plugins/plugin-openai/utils/config.ts: large = gpt-5,
    // small/nano = gpt-5-mini. detour collapses coding/utility onto the same two tiers.
    public static let openAIModelID = "gpt-5"
    public static let openAICodingModelID = "gpt-5"
    public static let openAIFastModelID = "gpt-5-mini"
    public static let openAIUtilityModelID = "gpt-5-mini"
    public static let openAIEmbeddingModelID = "text-embedding-3-small"

    public static let openRouterProviderID = "openrouter"
    public static let openRouterModelID = "openai/gpt-5"
    public static let openRouterCodingModelID = "openai/gpt-5"
    public static let openRouterFastModelID = "openai/gpt-5-mini"
    public static let openRouterUtilityModelID = "openai/gpt-5-mini"

    public static let anthropicProviderID = "anthropic"
    public static let anthropicModelID = "claude-opus-4-7"
    public static let anthropicCodingModelID = "claude-sonnet-4-6"
    public static let anthropicFastModelID = "claude-haiku-4-5-20251001"

    public static let detourCloudProviderID = "detour-cloud"
    public static let detourCloudModelID = "auto"

    // Dev proxy: a localhost OpenAI-compatible endpoint that rotates free
    // tiers so development/testing doesn't burn paid quota. Opt-in (select
    // it as the active provider); the key lives in Keychain under
    // dev-proxy.api_key. `auto` lets the proxy's router pick a free model.
    public static let devProxyProviderID = "dev-proxy"
    public static let devProxyBaseURL = "http://localhost:3001/v1"
    public static let devProxyModelID = "auto"
    public static let devProxyCodingModelID = "qwen/qwen3-coder:free"

    public static let localOpenAIProviderID = "local-openai"
    public static let localOpenAIModelID = "gemma4:e4b"
    public static let localOpenAIFallbackModelID = "gemma4:e2b"
    public static let phoneFunctionCallingModelID = "functiongemma:270m"

    public static let localMLXProviderID = "mlx-local"
    public static let localMLXModelID = "mlx-community/gemma-4-e4b-it-4bit"
    public static let localMLXFallbackModelID = "mlx-community/gemma-4-e2b-it-4bit"
    public static let localLiteRTProviderID = "litert-local"
    public static let localLiteRTModelID = "gemma-4-E4B-it"
    public static let localFoundationProviderID = "apple-foundation"
    public static let localFoundationModelID = "apple-on-device"
}

public enum UnifiedModelCatalog {
    /// All models, excluding NSFW. Use `allIncludingNSFW` to include adult content
    /// (requires user confirmation in the UI before switching to that view).
    public static var all: [UnifiedModelEntry] {
        (cloud + localMLX + local).filter { $0.contentRating == .general }
    }

    /// All models including NSFW content. The UI layer MUST present a
    /// confirmation dialog before showing these results to the user.
    public static var allIncludingNSFW: [UnifiedModelEntry] {
        cloud + localMLX + local + nsfwLocalMLX
    }

    /// NSFW models only. Requires explicit user opt-in.
    public static var nsfwModels: [UnifiedModelEntry] {
        nsfwLocalMLX
    }

    public static var interactive: [UnifiedModelEntry] {
        all.filter { entry in
            entry.capabilities.contains(.textGeneration)
            && !entry.capabilities.contains(.embedding)
            && !entry.capabilities.contains(.reranking)
            && entry.providerID != ModelDefaults.localFoundationProviderID
            && (entry.roles.contains(.agent) || entry.roles.contains(.coder) || entry.roles.contains(.vision))
        }
    }

    public static var embeddings: [UnifiedModelEntry] {
        models(withCapability: .embedding)
    }

    public static var rerankers: [UnifiedModelEntry] {
        models(withCapability: .reranking)
    }

    public static var speechToText: [UnifiedModelEntry] {
        models(withCapability: .speechToText)
    }

    public static var textToSpeech: [UnifiedModelEntry] {
        models(withCapability: .textToSpeech)
    }

    public static var imageGeneration: [UnifiedModelEntry] {
        models(withCapability: .imageGeneration)
    }

    public static func models(withRole role: ModelRole) -> [UnifiedModelEntry] {
        all.filter { $0.roles.contains(role) }
    }

    public static func models(withCapability capability: ModelCapability) -> [UnifiedModelEntry] {
        all.filter { $0.capabilities.contains(capability) }
    }

    public static var cloud: [UnifiedModelEntry] {
        CloudCatalog.all.map { entry in
            var roles: Set<ModelRole> = [.agent, .fallback]
            if entry.supportsToolCalling { roles.insert(.coder) }
            if entry.supportsVision { roles.insert(.vision) }

            return UnifiedModelEntry(
                id: entry.id,
                modelID: entry.routeModelID,
                providerID: entry.providerID,
                displayName: entry.displayName,
                family: entry.family,
                runtime: runtime(for: entry.providerID),
                contextWindow: entry.contextWindow,
                capabilities: cloudCapabilities(entry),
                roles: roles,
                supportsReasoningEffort: entry.supportsReasoningEffort,
                blurb: entry.blurb
            )
        }
    }

    public static var local: [UnifiedModelEntry] {
        ModelCatalog.curatedModels.map { entry in
            let providerID = providerID(for: entry)
            return UnifiedModelEntry(
                id: "\(providerID):\(entry.ollamaTag ?? entry.id)",
                modelID: entry.ollamaTag ?? entry.id,
                providerID: providerID,
                displayName: entry.name,
                family: entry.family,
                runtime: runtime(forLocalProviderID: providerID),
                estimatedMemoryGB: entry.estimatedMemoryGB,
                capabilities: entry.capabilities,
                roles: entry.defaultRoles,
                blurb: entry.description,
                installCommands: entry.installCommands
            )
        }
    }

    public static var localMLX: [UnifiedModelEntry] {
        [
            // ═══════════════════════════════════════════════════════
            // ── Gemma 4 family (Google · April 2026) ─────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "gemma4-e2b",
                modelID: ModelDefaults.localMLXFallbackModelID,
                displayName: "Gemma 4 E2B",
                family: "Gemma 4",
                estimatedMemoryGB: 3.2,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision, .ocr, .speechToText],
                roles: [.agent, .coder, .vision, .transcriber, .fast],
                blurb: "Edge Gemma 4. Trimodal (text+image+audio). Runs on iPhone."
            ),
            mlxEntry(
                id: "gemma4-e4b",
                modelID: ModelDefaults.localMLXModelID,
                displayName: "Gemma 4 E4B",
                family: "Gemma 4",
                estimatedMemoryGB: 5.0,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision, .ocr, .speechToText],
                roles: [.agent, .coder, .vision, .transcriber],
                blurb: "Default local Gemma 4. Trimodal, strong all-rounder."
            ),
            mlxEntry(
                id: "gemma4-26b-moe",
                modelID: "mlx-community/gemma-4-26b-it-4bit",
                displayName: "Gemma 4 26B MoE",
                family: "Gemma 4",
                estimatedMemoryGB: 8.0,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision, .ocr],
                roles: [.agent, .coder, .vision],
                blurb: "MoE Gemma 4 — 26B total, 3.8B active. Fast + smart."
            ),
            mlxEntry(
                id: "gemma4-31b",
                modelID: "mlx-community/gemma-4-31b-it-4bit",
                displayName: "Gemma 4 31B Dense",
                family: "Gemma 4",
                estimatedMemoryGB: 18.0,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision, .ocr],
                roles: [.agent, .coder, .vision],
                blurb: "Flagship dense Gemma 4. 256K context. Needs 24GB+."
            ),

            // ── Gemma 4 abliterated ──────────────────────────────
            mlxEntry(
                id: "gemma4-e4b-abliterated",
                modelID: "mlx-community/gemma-4-e4b-it-abliterated-4bit",
                displayName: "Gemma 4 E4B ⛓️‍💥",
                family: "Gemma 4",
                estimatedMemoryGB: 5.0,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision],
                roles: [.agent, .coder, .vision],
                blurb: "Abliterated Gemma 4. No refusals, full capability."
            ),
            mlxEntry(
                id: "gemma4-31b-abliterated",
                modelID: "mlx-community/gemma-4-31b-it-abliterated-4bit",
                displayName: "Gemma 4 31B ⛓️‍💥",
                family: "Gemma 4",
                estimatedMemoryGB: 18.0,
                capabilities: [.textGeneration, .coding, .structuredOutput, .vision],
                roles: [.agent, .coder, .vision],
                blurb: "Abliterated flagship Gemma 4. Uncensored 31B dense."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Qwen 3.5 family (Alibaba · Feb 2026) ─────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "qwen35-4b",
                modelID: "mlx-community/Qwen3.5-4B-4bit",
                displayName: "Qwen 3.5 4B",
                family: "Qwen 3.5",
                estimatedMemoryGB: 3.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder, .fast],
                blurb: "Tiny Qwen 3.5. Hybrid GDN+MoE arch. iPhone-safe."
            ),
            mlxEntry(
                id: "qwen35-9b",
                modelID: "mlx-community/Qwen3.5-9B-4bit",
                displayName: "Qwen 3.5 9B",
                family: "Qwen 3.5",
                estimatedMemoryGB: 5.5,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Sweet-spot Qwen 3.5. Great agent backbone for 16GB."
            ),
            mlxEntry(
                id: "qwen35-27b",
                modelID: "mlx-community/Qwen3.5-27B-4bit",
                displayName: "Qwen 3.5 27B",
                family: "Qwen 3.5",
                estimatedMemoryGB: 16.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Large Qwen 3.5 dense. Near-frontier reasoning."
            ),
            mlxEntry(
                id: "qwen35-35b-a3b",
                modelID: "mlx-community/Qwen3.5-35B-A3B-4bit",
                displayName: "Qwen 3.5 35B MoE",
                family: "Qwen 3.5",
                estimatedMemoryGB: 8.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "MoE Qwen 3.5 — 35B total, 3B active. 100+ t/s on M4."
            ),

            // ── Qwen 3.5 abliterated ────────────────────────────
            mlxEntry(
                id: "qwen35-27b-abliterated",
                modelID: "mlx-community/Qwen3.5-27B-Claude-Distilled-abliterated-4bit",
                displayName: "Qwen 3.5 27B ⛓️‍💥",
                family: "Qwen 3.5",
                estimatedMemoryGB: 16.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Abliterated Claude-distilled Qwen 3.5. Top uncensored."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Qwen 3.6 (Alibaba · April 2026) ─────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "qwen36-35b-a3b",
                modelID: "mlx-community/Qwen3.6-35B-A3B-4bit",
                displayName: "Qwen 3.6 35B MoE",
                family: "Qwen 3.6",
                estimatedMemoryGB: 8.5,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Latest open-weight Qwen. MoE speed king, 100+ t/s."
            ),

            // ── Qwen 3.6 abliterated / uncensored ─────────────────
            mlxEntry(
                id: "qwen36-35b-a3b-uncensored",
                modelID: "HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive",
                displayName: "Qwen 3.6 35B MoE ⛓️\u{200d}💥",
                family: "Qwen 3.6",
                estimatedMemoryGB: 8.5,
                capabilities: [.textGeneration, .coding, .vision, .toolCalling, .structuredOutput],
                roles: [.agent, .coder, .vision],
                blurb: "Apr 2026. Aggressively uncensored Qwen 3.6 MoE. 2M+ downloads."
            ),

            // ═══════════════════════════════════════════════════════
            // ── GLM-5 (Zhipu AI · Feb 2026) ──────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "glm5-40b",
                modelID: "mlx-community/GLM-5-40B-4bit",
                displayName: "GLM-5 40B Active",
                family: "GLM-5",
                estimatedMemoryGB: 24.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Zhipu's flagship. 744B MoE, 40B active. Needs 32GB+."
            ),
            mlxEntry(
                id: "glm47-flash",
                modelID: "mlx-community/GLM-4.7-Flash-4bit",
                displayName: "GLM-4.7 Flash",
                family: "GLM",
                estimatedMemoryGB: 5.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder, .fast],
                blurb: "Fast GLM for coding and agentic tasks. Great value."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Mistral Small 4 (Mistral · March 2026) ───────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "mistral-small-4",
                modelID: "mlx-community/Mistral-Small-4-119B-6B-4bit",
                displayName: "Mistral Small 4",
                family: "Mistral Small 4",
                estimatedMemoryGB: 7.0,
                capabilities: [.textGeneration, .toolCalling, .vision, .structuredOutput],
                roles: [.agent, .vision],
                blurb: "119B MoE, 6B active. Multimodal + agentic. Apache 2.0."
            ),

            // ═══════════════════════════════════════════════════════
            // ── DeepSeek V4 Flash (DeepSeek · April 2026) ────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "deepseek-v4-flash",
                modelID: "mlx-community/DeepSeek-V4-Flash-284B-4bit",
                displayName: "DeepSeek V4 Flash",
                family: "DeepSeek V4",
                estimatedMemoryGB: 18.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "284B MoE, 13B active. Elite math + coding. Needs 24GB+."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Phi-4 family (Microsoft · Jan 2026) ──────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "phi4-mini-3.8b",
                modelID: "mlx-community/phi-4-mini-instruct-4bit",
                displayName: "Phi-4 Mini 3.8B",
                family: "Phi-4",
                estimatedMemoryGB: 2.8,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder, .fast],
                blurb: "Microsoft's edge powerhouse. Best-in-class at 3.8B."
            ),
            mlxEntry(
                id: "phi4-14b",
                modelID: "mlx-community/phi-4-14b-instruct-4bit",
                displayName: "Phi-4 14B",
                family: "Phi-4",
                estimatedMemoryGB: 9.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput],
                roles: [.agent, .coder],
                blurb: "Reasoning-focused mid-size. Strong math and logic."
            ),

            // ═══════════════════════════════════════════════════════
            // ── TTS — Text-to-Speech (2026) ──────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "qwen3-tts-0.6b",
                modelID: "mlx-community/Qwen3-TTS-0.6B-bf16",
                displayName: "Qwen3-TTS 0.6B",
                family: "Qwen3-TTS",
                estimatedMemoryGB: 1.2,
                capabilities: [.textToSpeech, .voiceCloning],
                roles: [.speaker, .fast],
                blurb: "Jan 2026. 10+ languages, 3s voice cloning, streaming."
            ),
            mlxEntry(
                id: "qwen3-tts-1.7b",
                modelID: "mlx-community/Qwen3-TTS-1.7B-bf16",
                displayName: "Qwen3-TTS 1.7B",
                family: "Qwen3-TTS",
                estimatedMemoryGB: 3.5,
                capabilities: [.textToSpeech, .voiceCloning, .voiceDesign],
                roles: [.speaker],
                blurb: "Jan 2026. Expressive, emotion-controllable TTS."
            ),
            mlxEntry(
                id: "fish-speech-s2",
                modelID: "mlx-community/fish-speech-s2-bf16",
                displayName: "Fish Speech S2",
                family: "Fish Speech",
                estimatedMemoryGB: 2.0,
                capabilities: [.textToSpeech, .voiceCloning],
                roles: [.speaker],
                blurb: "Mar 2026. Dual-AR architecture. Best multilingual TTS."
            ),
            mlxEntry(
                id: "spark-tts-0.5b",
                modelID: "mlx-community/Spark-TTS-0.5B-bf16",
                displayName: "Spark TTS 0.5B",
                family: "Spark",
                estimatedMemoryGB: 1.0,
                capabilities: [.textToSpeech],
                roles: [.speaker, .fast],
                blurb: "Feb 2026. Single-stream LLM TTS. Tiny and fast."
            ),
            mlxEntry(
                id: "kokoro-tts",
                modelID: "mlx-community/Kokoro-82M-v1.1-bf16",
                displayName: "Kokoro TTS 82M",
                family: "Kokoro",
                estimatedMemoryGB: 0.15,
                capabilities: [.textToSpeech],
                roles: [.speaker, .fast],
                blurb: "Ultra-light gold standard TTS. <1MB. iPhone-safe."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Image Generation (2026) ──────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "bonsai-image-4b",
                modelID: "mlx-community/bonsai-image-ternary-4B-2bit",
                displayName: "Bonsai Image 4B",
                family: "Bonsai",
                estimatedMemoryGB: 1.2,
                capabilities: [.imageGeneration],
                roles: [.imageGenerator, .fast],
                blurb: "May 2026. PrismML ternary 2-bit. Runs on iPhone!"
            ),
            mlxEntry(
                id: "flux2-klein-4b",
                modelID: "mlx-community/FLUX.2-klein-4B-4bit",
                displayName: "FLUX.2 Klein 4B",
                family: "FLUX.2",
                estimatedMemoryGB: 3.0,
                capabilities: [.imageGeneration],
                roles: [.imageGenerator],
                blurb: "Jan 2026. Distilled FLUX.2 for consumer hardware. Apache 2.0."
            ),
            mlxEntry(
                id: "hidream-o1-8b",
                modelID: "mlx-community/HiDream-O1-Image-8B-4bit",
                displayName: "HiDream-O1 Image 8B",
                family: "HiDream",
                estimatedMemoryGB: 6.0,
                capabilities: [.imageGeneration, .imageEditing],
                roles: [.imageGenerator, .imageEditor],
                blurb: "May 2026. Unified pixel transformer. 2K res. MIT license."
            ),
            mlxEntry(
                id: "glm-image-16b",
                modelID: "mlx-community/GLM-Image-16B-4bit",
                displayName: "GLM-Image 16B",
                family: "GLM-Image",
                estimatedMemoryGB: 10.0,
                capabilities: [.imageGeneration, .imageEditing],
                roles: [.imageGenerator, .imageEditor],
                blurb: "Jan 2026. Hybrid AR+diffusion. Best text rendering."
            ),
            mlxEntry(
                id: "lance-3b-mlx",
                modelID: "RockTalk/Lance-3B-MLX",
                displayName: "Lance 3B",
                family: "Lance",
                estimatedMemoryGB: 3.5,
                capabilities: [.imageGeneration, .videoGeneration],
                roles: [.imageGenerator, .videoGenerator],
                blurb: "May 2026. ByteDance unified image+video MoE. Native MLX."
            ),
            mlxEntry(
                id: "z-image-turbo",
                modelID: "Tongyi-MAI/Z-Image-Turbo",
                displayName: "Z-Image Turbo",
                family: "Z-Image",
                estimatedMemoryGB: 5.0,
                capabilities: [.imageGeneration],
                roles: [.imageGenerator, .fast],
                blurb: "2026. Alibaba Tongyi turbo-distilled image gen. 4-step."
            ),
            mlxEntry(
                id: "lens-turbo",
                modelID: "microsoft/Lens-Turbo",
                displayName: "Lens Turbo",
                family: "Lens",
                estimatedMemoryGB: 4.0,
                capabilities: [.imageGeneration],
                roles: [.imageGenerator, .fast],
                blurb: "2026. Microsoft fast image gen. Turbo distilled."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Video Generation (2026) ──────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "ltx-video-2.3-q4",
                modelID: "gajesh/LTX-2.3-mlx-q4",
                displayName: "LTX-Video 2.3 (Q4)",
                family: "LTX",
                estimatedMemoryGB: 8.0,
                capabilities: [.videoGeneration],
                roles: [.videoGenerator, .fast],
                blurb: "Mar 2026. 4-bit MLX quant. Fits 16GB. 4K + audio."
            ),
            mlxEntry(
                id: "ltx-video-2.3",
                modelID: "mlx-community/LTX-2.3-22B-4bit",
                displayName: "LTX-Video 2.3 (Full)",
                family: "LTX",
                estimatedMemoryGB: 14.0,
                capabilities: [.videoGeneration],
                roles: [.videoGenerator],
                blurb: "Mar 2026. 4K + native audio. Higher quality. Needs 32GB."
            ),
            mlxEntry(
                id: "wan-2.7-1.3b",
                modelID: "mlx-community/Wan-2.7-T2V-1.3B-4bit",
                displayName: "Wan 2.7 Lite 1.3B",
                family: "Wan",
                estimatedMemoryGB: 3.0,
                capabilities: [.videoGeneration],
                roles: [.videoGenerator],
                blurb: "Apr 2026. Alibaba text-to-video lite. Fits on 16GB."
            ),
            mlxEntry(
                id: "wan-2.7-14b",
                modelID: "mlx-community/Wan-2.7-T2V-14B-4bit",
                displayName: "Wan 2.7 14B",
                family: "Wan",
                estimatedMemoryGB: 10.0,
                capabilities: [.videoGeneration],
                roles: [.videoGenerator],
                blurb: "Apr 2026. Full MoE video gen. High motion quality."
            ),
            mlxEntry(
                id: "wan22-ti2v-5b",
                modelID: "QuantStack/Wan2.2-TI2V-5B-GGUF",
                displayName: "Wan 2.2 TI2V 5B",
                family: "Wan",
                estimatedMemoryGB: 4.0,
                capabilities: [.videoGeneration, .imageEditing],
                roles: [.videoGenerator],
                blurb: "2026. Wan 2.2 text+image-to-video. GGUF quantized."
            ),
            mlxEntry(
                id: "hunyuanvideo-1.5",
                modelID: "Dj-Icq/HunyuanVideo-1.5_T2V_720p-GGUF",
                displayName: "HunyuanVideo 1.5",
                family: "HunyuanVideo",
                estimatedMemoryGB: 12.0,
                capabilities: [.videoGeneration],
                roles: [.videoGenerator],
                blurb: "2026. Tencent text-to-video. 720p. GGUF quantized."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Embeddings (2026) ────────────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "qwen3-embedding-0.6b",
                modelID: "mlx-community/Qwen3-Embedding-0.6B-4bit",
                displayName: "Qwen3-Embedding 0.6B",
                family: "Qwen3",
                estimatedMemoryGB: 0.5,
                capabilities: [.embedding],
                roles: [.embedder, .fast],
                blurb: "100+ languages. Instruction-aware. iPhone-safe."
            ),
            mlxEntry(
                id: "qwen3-vl-embedding",
                modelID: "mlx-community/Qwen3-VL-Embedding-4bit",
                displayName: "Qwen3-VL-Embedding",
                family: "Qwen3",
                estimatedMemoryGB: 2.5,
                capabilities: [.embedding, .vision],
                roles: [.embedder],
                blurb: "Jan 2026. Multimodal embeddings — text + image + video."
            ),
            mlxEntry(
                id: "embedding-gemma-300m",
                modelID: "mlx-community/EmbeddingGemma-300M-bf16",
                displayName: "EmbeddingGemma 300M",
                family: "Gemma",
                estimatedMemoryGB: 0.2,
                capabilities: [.embedding],
                roles: [.embedder, .fast],
                blurb: "Google DeepMind. Ultra-light on-device embeddings."
            ),
            mlxEntry(
                id: "harrier-0.6b",
                modelID: "mlx-community/Harrier-oss-v1-0.6B-4bit",
                displayName: "Harrier 0.6B",
                family: "Harrier",
                estimatedMemoryGB: 0.5,
                capabilities: [.embedding],
                roles: [.embedder],
                blurb: "Apr 2026. Microsoft's SOTA small retrieval model."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Reranking (2026) ─────────────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "qwen3-reranker-0.6b",
                modelID: "mlx-community/Qwen3-Reranker-0.6B-4bit",
                displayName: "Qwen3-Reranker 0.6B",
                family: "Qwen3",
                estimatedMemoryGB: 0.5,
                capabilities: [.reranking],
                roles: [.reranker, .fast],
                blurb: "Cross-encoder reranker. Boosts RAG precision."
            ),
            mlxEntry(
                id: "qwen3-reranker-4b",
                modelID: "mlx-community/Qwen3-Reranker-4B-4bit",
                displayName: "Qwen3-Reranker 4B",
                family: "Qwen3",
                estimatedMemoryGB: 3.0,
                capabilities: [.reranking],
                roles: [.reranker],
                blurb: "Higher-accuracy reranker for complex RAG pipelines."
            ),
            mlxEntry(
                id: "ms-marco-minilm-l6-v2",
                modelID: "cross-encoder/ms-marco-MiniLM-L6-v2",
                displayName: "MS-MARCO MiniLM L6",
                family: "MiniLM",
                estimatedMemoryGB: 0.1,
                capabilities: [.reranking],
                roles: [.reranker, .fast],
                blurb: "22M params. Classic cross-encoder reranker. Near-zero RAM."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Sentiment / Classification ─────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "cryptobert",
                modelID: "ElKulako/cryptobert",
                displayName: "CryptoBERT",
                family: "BERT",
                estimatedMemoryGB: 0.1,
                capabilities: [.sentimentAnalysis, .classification],
                roles: [.router],
                blurb: "Crypto-native BERT. Twitter/Reddit sentiment. Bullish/bearish/neutral."
            ),
            mlxEntry(
                id: "twitter-roberta-sentiment",
                modelID: "cardiffnlp/twitter-roberta-base-sentiment-latest",
                displayName: "Twitter RoBERTa Sentiment",
                family: "RoBERTa",
                estimatedMemoryGB: 0.1,
                capabilities: [.sentimentAnalysis, .classification],
                roles: [.router],
                blurb: "Cardiff NLP. General social-media sentiment. 3-class. ~125M params."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Vision / VLM (2026) ──────────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "qwen35-vl-7b",
                modelID: "mlx-community/Qwen3.5-VL-7B-4bit",
                displayName: "Qwen 3.5 VL 7B",
                family: "Qwen 3.5",
                estimatedMemoryGB: 5.0,
                capabilities: [.textGeneration, .vision, .ocr, .structuredOutput, .documentLayout],
                roles: [.vision, .ocrEngine],
                blurb: "Feb 2026. Frontier VLM. OCR in 50+ languages, GUI automation."
            ),
            mlxEntry(
                id: "glm45v-thinking",
                modelID: "mlx-community/GLM-4.5V-Thinking-4bit",
                displayName: "GLM-4.5V Thinking",
                family: "GLM",
                estimatedMemoryGB: 8.0,
                capabilities: [.textGeneration, .vision, .ocr, .documentLayout, .structuredOutput],
                roles: [.vision, .ocrEngine, .agent],
                blurb: "2026. 3D spatial perception + document understanding."
            ),
            mlxEntry(
                id: "falcon-ocr",
                modelID: "tiiuae/Falcon-OCR",
                displayName: "Falcon-OCR",
                family: "Falcon",
                estimatedMemoryGB: 1.0,
                capabilities: [.ocr, .vision, .documentLayout],
                roles: [.ocrEngine, .vision],
                blurb: "Feb 2026. TII's dedicated OCR VLM. SOTA at <1B. Apache 2.0."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Music Generation (2026) ──────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "musicgen-medium",
                modelID: "mlx-community/musicgen-medium-bf16",
                displayName: "MusicGen Medium",
                family: "MusicGen",
                estimatedMemoryGB: 3.0,
                capabilities: [.musicGeneration],
                roles: [.musicGenerator],
                blurb: "Text-to-music. 30s instrumental clips on-device."
            ),

            // ═══════════════════════════════════════════════════════
            // ── 3D Generation / Reconstruction (2026) ────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "trellis2-4b",
                modelID: "microsoft/TRELLIS.2-4B",
                displayName: "TRELLIS.2 4B",
                family: "TRELLIS",
                estimatedMemoryGB: 12.0,
                capabilities: [.threeD, .threeDReconstruction],
                roles: [.threeDGenerator],
                blurb: "Dec 2025. Microsoft image-to-3D. PBR materials. 1536³ res. MIT."
            ),
            mlxEntry(
                id: "hunyuan3d-2.1",
                modelID: "tencent/Hunyuan3D-2.1",
                displayName: "Hunyuan3D 2.1",
                family: "Hunyuan3D",
                estimatedMemoryGB: 18.0,
                capabilities: [.threeD, .threeDReconstruction],
                roles: [.threeDGenerator],
                blurb: "2025. Tencent image-to-3D. PBR textures. MLX port available."
            ),
            mlxEntry(
                id: "hunyuan3d-2mini",
                modelID: "Dynamo137/Hunyuan3D-2mini",
                displayName: "Hunyuan3D 2 Mini",
                family: "Hunyuan3D",
                estimatedMemoryGB: 8.0,
                capabilities: [.threeD, .threeDReconstruction],
                roles: [.threeDGenerator, .fast],
                blurb: "2025. Lightweight Hunyuan3D. Fits 16GB Macs."
            ),
            mlxEntry(
                id: "pixal3d",
                modelID: "TencentARC/Pixal3D",
                displayName: "Pixal3D",
                family: "Pixal3D",
                estimatedMemoryGB: 14.0,
                capabilities: [.threeD, .threeDReconstruction],
                roles: [.threeDGenerator],
                blurb: "2026. TencentARC pixel-aligned 3D. SIGGRAPH 2026. MIT."
            ),
            mlxEntry(
                id: "vgg-ttt",
                modelID: "nvidia/vgg-ttt",
                displayName: "VGG-T³",
                family: "VGG-T³",
                estimatedMemoryGB: 3.0,
                capabilities: [.threeDReconstruction, .depthEstimation],
                roles: [.threeDGenerator, .fast],
                blurb: "May 2026. NVIDIA 1.2B. Images-to-3D reconstruction. Linear scaling."
            ),

            // ═══════════════════════════════════════════════════════
            // ── World Generation (2026) ──────────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "hy-world-2",
                modelID: "tencent/HY-World-2.0",
                displayName: "HY-World 2.0",
                family: "HY-World",
                estimatedMemoryGB: 20.0,
                capabilities: [.worldGeneration, .threeD],
                roles: [.worldGenerator, .threeDGenerator],
                blurb: "Apr 2026. Tencent world gen. Text/image-to-3D worlds. Unity/UE."
            ),

            // ═══════════════════════════════════════════════════════
            // ── Community Agent LLMs (2026) ──────────────────────
            // ═══════════════════════════════════════════════════════
            mlxEntry(
                id: "gemma4-e4b-agentic-opus",
                modelID: "deadbydawn101/gemma-4-E4B-Agentic-Opus-Reasoning-GeminiCLI-mlx-4bit",
                displayName: "Gemma 4 E4B Agentic Opus",
                family: "Gemma 4",
                estimatedMemoryGB: 3.0,
                capabilities: [.textGeneration, .coding, .toolCalling, .structuredOutput, .vision],
                roles: [.agent, .coder],
                blurb: "Mar 2026. Claude Opus-distilled Gemma 4. Fused LoRA. Native MLX."
            ),
            mlxEntry(
                id: "nexus-1.5b",
                modelID: "mradermacher/nexus-1.5b-i1-GGUF",
                displayName: "Nexus 1.5B",
                family: "Nexus",
                estimatedMemoryGB: 1.5,
                capabilities: [.textGeneration, .structuredOutput],
                roles: [.agent, .fast],
                blurb: "May 2026. Qwen2-based math/reasoning. CoT. GGUF imatrix. Apache 2.0."
            ),
            mlxEntry(
                id: "nvidia-nitrogen",
                modelID: "nvidia/NitroGen",
                displayName: "NitroGen",
                family: "NitroGen",
                estimatedMemoryGB: 1.0,
                capabilities: [.vision, .gaming],
                roles: [.gamingAgent],
                blurb: "Jan 2026. NVIDIA 493M gaming agent. SigLip2+DiT. Plays 1000+ games from pixels."
            ),
        ]
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - NSFW / Adult LoRA Adapters (gated)
    // ═══════════════════════════════════════════════════════════════════
    //
    // These are LoRA adapters for video generation base models (LTX-2.3,
    // Wan 2.x). They require explicit user confirmation before they appear
    // in the model picker. The UI must present a consent gate.
    //
    // Base models required:
    //   - LTX-2.3  → localMLX:ltx-video-2.3
    //   - Wan 2.1  → localMLX:wan-2.7-14b (or compatible Wan)
    // ═══════════════════════════════════════════════════════════════════

    public static var nsfwLocalMLX: [UnifiedModelEntry] {
        [
            nsfwLoraEntry(
                id: "nsfw-ltx23-oral-suite",
                modelID: "Muapi/ltx2-oral-suite",
                displayName: "Oral Suite (LTX 2.3 LoRA)",
                baseModel: "Muapi/ltx2-oral-suite",
                blurb: "NSFW. LTX-2.3 oral video LoRA adapter."
            ),
            nsfwLoraEntry(
                id: "nsfw-ltx23-sex-thrust",
                modelID: "Muapi/ltx2-sex-thrust",
                displayName: "Sex Thrust (LTX 2.3 LoRA)",
                baseModel: "Muapi/ltx2-sex-thrust",
                blurb: "NSFW. LTX-2.3 thrust motion LoRA adapter."
            ),
            nsfwLoraEntry(
                id: "nsfw-ltx23-riding-pov",
                modelID: "Muapi/ltx-2.3-riding-pov-i2v",
                displayName: "Riding POV I2V (LTX 2.3 LoRA)",
                baseModel: "Muapi/ltx-2.3-riding-pov-i2v",
                blurb: "NSFW. LTX-2.3 POV riding image-to-video LoRA."
            ),
            nsfwLoraEntry(
                id: "nsfw-ltx23-pov-tf",
                modelID: "Muapi/ltx2-pov-tittyfucking-lora",
                displayName: "POV TF (LTX 2.3 LoRA)",
                baseModel: "Muapi/ltx2-pov-tittyfucking-lora",
                blurb: "NSFW. LTX-2.3 POV LoRA adapter."
            ),
            nsfwLoraEntry(
                id: "nsfw-ltx23-cunnilingus",
                modelID: "Muapi/cunnilingus-ltx2.3-video-lora-k3nk",
                displayName: "Cunnilingus (LTX 2.3 LoRA)",
                baseModel: "Muapi/cunnilingus-ltx2.3-video-lora-k3nk",
                blurb: "NSFW. LTX-2.3 cunnilingus video LoRA."
            ),
            nsfwLoraEntry(
                id: "nsfw-ltx23-synth-pussy",
                modelID: "Muapi/synth-pussy-ltx-2.3",
                displayName: "Synth Pussy (LTX 2.3 LoRA)",
                baseModel: "Muapi/synth-pussy-ltx-2.3",
                blurb: "NSFW. LTX-2.3 synthetic LoRA adapter."
            ),
            nsfwLoraEntry(
                id: "nsfw-ltx23-beej",
                modelID: "Muapi/beej",
                displayName: "BJ (LTX 2.3 LoRA)",
                baseModel: "Muapi/beej",
                blurb: "NSFW. LTX-2.3 oral LoRA adapter."
            ),
            nsfwLoraEntry(
                id: "nsfw-wan-nude-art",
                modelID: "Muapi/wan-nude-art",
                displayName: "Nude Art (Wan LoRA)",
                baseModel: "Muapi/wan-nude-art",
                blurb: "NSFW. Wan nude art video LoRA. Artistic style."
            ),
            nsfwLoraEntry(
                id: "nsfw-doggy-missionary-3d",
                modelID: "Muapi/doggy-missionary-3d",
                displayName: "Doggy/Missionary 3D (LoRA)",
                baseModel: "Muapi/doggy-missionary-3d",
                blurb: "NSFW. 3D-style position video LoRA adapter."
            ),

            // ─── NSFW Image Generation LoRAs ─────────────────────
            // Base models: FLUX.1-dev, FLUX.2-klein, Bonsai, HiDream
            // ─────────────────────────────────────────────────────────

            nsfwImageLoraEntry(
                id: "nsfw-flux-uncensored-v2",
                modelID: "enhanceaiteam/Flux-uncensored-v2",
                displayName: "FLUX Uncensored V2 (LoRA)",
                baseModel: "black-forest-labs/FLUX.1-dev",
                blurb: "NSFW. FLUX.1 uncensored LoRA. Most popular, high quality."
            ),
            nsfwImageLoraEntry(
                id: "nsfw-flux-lora-uncensored",
                modelID: "aifeifei798/flux-lora-uncensored",
                displayName: "FLUX Uncensored (LoRA)",
                baseModel: "black-forest-labs/FLUX.1-dev",
                blurb: "NSFW. Original FLUX uncensored LoRA. Widely used."
            ),
            nsfwImageLoraEntry(
                id: "nsfw-flux-heartsync",
                modelID: "Heartsync/Flux-NSFW-uncensored",
                displayName: "FLUX NSFW Heartsync (LoRA)",
                baseModel: "black-forest-labs/FLUX.1-dev",
                blurb: "NSFW. Heartsync FLUX uncensored LoRA. Photorealistic."
            ),
            nsfwImageLoraEntry(
                id: "nsfw-flux-uncensored-hvai",
                modelID: "hvai/fluxlora",
                displayName: "FLUX NSFW hvai (LoRA)",
                baseModel: "black-forest-labs/FLUX.1-dev",
                blurb: "NSFW. hvai Flux-NSFW-uncensored LoRA. Community staple."
            ),
            nsfwImageLoraEntry(
                id: "nsfw-flux-uncensored-v2-ryouko",
                modelID: "Ryouko65777/Flux-Uncensored-V2",
                displayName: "FLUX Uncensored V2 Ryouko (LoRA)",
                baseModel: "black-forest-labs/FLUX.1-dev",
                blurb: "NSFW. Ryouko's FLUX uncensored V2. High detail."
            ),

            // ─── NSFW Chat / Roleplay Models ──────────────────────
            nsfwLoraEntry(
                id: "nsfw-tifa-deepsexv2-7b",
                modelID: "ValueFX9507/Tifa-DeepsexV2-7b-MGRPO-GGUF-Q4",
                displayName: "Tifa DeepsexV2 7B (Q4)",
                baseModel: "qwen/qwen7b",
                blurb: "NSFW. Qwen 7B RL-tuned roleplay. GGUF Q4. Chinese/English."
            ),
        ]
    }

    public static func providerDisplayName(_ providerID: String) -> String {
        switch providerID {
        case ModelDefaults.routerProviderID: return "Auto"
        case ModelDefaults.codexProviderID: return "ChatGPT"
        case ModelDefaults.openAIProviderID: return "OpenAI"
        case ModelDefaults.openRouterProviderID: return "OpenRouter"
        case ModelDefaults.detourCloudProviderID: return "Detour Cloud"
        case ModelDefaults.devProxyProviderID: return "Dev Proxy (free tiers)"
        case ModelDefaults.localOpenAIProviderID: return "Ollama / Local OpenAI"
        case ModelDefaults.localMLXProviderID: return "MLX Local"
        case ModelDefaults.localLiteRTProviderID: return "LiteRT Local"
        case ModelDefaults.localFoundationProviderID: return "Apple Foundation"
        default: return providerID.capitalized
        }
    }

    public static func defaultModel(providerID: String) -> String? {
        switch providerID {
        case ModelDefaults.codexProviderID: return ModelDefaults.codexModelID
        case ModelDefaults.openAIProviderID: return ModelDefaults.openAIModelID
        case ModelDefaults.anthropicProviderID: return ModelDefaults.anthropicModelID
        case ModelDefaults.openRouterProviderID: return ModelDefaults.openRouterModelID
        case ModelDefaults.detourCloudProviderID: return ModelDefaults.detourCloudModelID
        case ModelDefaults.devProxyProviderID: return ModelDefaults.devProxyModelID
        case ModelDefaults.localOpenAIProviderID: return ModelDefaults.localOpenAIModelID
        case ModelDefaults.localMLXProviderID: return ModelDefaults.localMLXModelID
        case ModelDefaults.localLiteRTProviderID: return ModelDefaults.localLiteRTModelID
        case ModelDefaults.localFoundationProviderID: return ModelDefaults.localFoundationModelID
        default: return nil
        }
    }

    public static func route(forCatalogID id: String) -> (providerID: String, modelID: String)? {
        guard let entry = all.first(where: { $0.id == id }) else { return nil }
        guard entry.providerID != ModelDefaults.routerProviderID else { return nil }
        guard entry.capabilities.contains(.textGeneration) else { return nil }
        return (entry.providerID, entry.modelID)
    }

    private static func providerID(for entry: CatalogEntry) -> String {
        if entry.sources.contains(.ollama) { return ModelDefaults.localOpenAIProviderID }
        if entry.sources.contains(.mlxCommunity) { return ModelDefaults.localMLXProviderID }
        if entry.sources.contains(.system) { return ModelDefaults.localFoundationProviderID }
        return ModelDefaults.localOpenAIProviderID
    }

    private static func runtime(for providerID: String) -> ModelRuntimeKind {
        switch providerID {
        case ModelDefaults.routerProviderID: return .router
        case ModelDefaults.codexProviderID: return .codex
        case ModelDefaults.openAIProviderID: return .openAI
        case ModelDefaults.openRouterProviderID: return .openRouter
        case ModelDefaults.detourCloudProviderID: return .detourCloud
        default: return .openRouter
        }
    }

    private static func runtime(forLocalProviderID providerID: String) -> ModelRuntimeKind {
        switch providerID {
        case ModelDefaults.localMLXProviderID: return .localMLX
        case ModelDefaults.localLiteRTProviderID: return .localLiteRT
        case ModelDefaults.localFoundationProviderID: return .localFoundation
        default: return .localOpenAI
        }
    }

    private static func cloudCapabilities(_ entry: CloudModelEntry) -> Set<ModelCapability> {
        var capabilities: Set<ModelCapability> = [.textGeneration]
        if entry.supportsToolCalling { capabilities.insert(.toolCalling) }
        if entry.supportsVision { capabilities.insert(.vision) }
        return capabilities
    }

    private static func mlxEntry(
        id: String,
        modelID: String,
        displayName: String,
        family: String,
        estimatedMemoryGB: Double,
        capabilities: Set<ModelCapability>,
        roles: Set<ModelRole>,
        blurb: String
    ) -> UnifiedModelEntry {
        UnifiedModelEntry(
            id: "\(ModelDefaults.localMLXProviderID):\(id)",
            modelID: modelID,
            providerID: ModelDefaults.localMLXProviderID,
            displayName: displayName,
            family: family,
            runtime: .localMLX,
            estimatedMemoryGB: estimatedMemoryGB,
            capabilities: capabilities,
            roles: roles,
            blurb: blurb,
            installCommands: [
                .mlxCommunity: "huggingface-cli download \(modelID)"
            ]
        )
    }

    /// Helper to create an NSFW LoRA adapter entry. Always rated `.nsfw`.
    private static func nsfwLoraEntry(
        id: String,
        modelID: String,
        displayName: String,
        baseModel: String,
        blurb: String
    ) -> UnifiedModelEntry {
        UnifiedModelEntry(
            id: "\(ModelDefaults.localMLXProviderID):\(id)",
            modelID: modelID,
            providerID: ModelDefaults.localMLXProviderID,
            displayName: displayName,
            family: "NSFW LoRA",
            runtime: .localMLX,
            estimatedMemoryGB: 0.5,  // LoRA adapters are lightweight
            capabilities: [.videoGeneration],
            roles: [.videoGenerator],
            blurb: blurb,
            installCommands: [
                .huggingFace: "huggingface-cli download \(modelID)"
            ],
            contentRating: .nsfw,
            baseModelID: baseModel
        )
    }

    /// Helper for NSFW image LoRA adapter entries.
    private static func nsfwImageLoraEntry(
        id: String,
        modelID: String,
        displayName: String,
        baseModel: String,
        blurb: String
    ) -> UnifiedModelEntry {
        UnifiedModelEntry(
            id: "\(ModelDefaults.localMLXProviderID):\(id)",
            modelID: modelID,
            providerID: ModelDefaults.localMLXProviderID,
            displayName: displayName,
            family: "NSFW LoRA",
            runtime: .localMLX,
            estimatedMemoryGB: 0.3,  // Image LoRAs are tiny
            capabilities: [.imageGeneration],
            roles: [.imageGenerator],
            blurb: blurb,
            installCommands: [
                .huggingFace: "huggingface-cli download \(modelID)"
            ],
            contentRating: .nsfw,
            baseModelID: baseModel
        )
    }
}
