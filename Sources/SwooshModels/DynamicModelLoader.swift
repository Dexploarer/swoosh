// SwooshModels/DynamicModelLoader.swift — Runtime model discovery + hardware-aware defaults — 0.9T
//
// Replaces the static "first model Ollama returns" auto-pick with a
// dynamic loader that:
//   1. Queries each local inference endpoint (Ollama, LM Studio, etc.)
//      via its native richer API (Ollama: /api/tags has params, size,
//      family, format) — not just /v1/models.
//   2. Asks Hugging Face for trending chat models the user might want
//      to install (only when the caller requests recommendations).
//   3. Resolves a hardware-aware default fallback: Gemma 4. The exact
//      tag is picked from the local `HardwareProfile.maxTier` so we
//      never propose a model the machine can't physically run.
//
// This module never hardcodes a chat-model "preference list" — the
// catalog of recommended families lives upstream (Hugging Face
// trending, Ollama Library popularity). The only opinion baked in
// here is "Gemma 4 is the default if nothing is installed yet."

import Foundation

// MARK: - Installed-model snapshot

public struct InstalledOllamaModel: Sendable, Codable, Identifiable {
    public let name: String
    public let family: String?        // "gemma4"
    public let parameterSize: String? // "2.6B"
    public let quantization: String?  // "Q4_K_M"
    public let format: String?        // "gguf"
    public let sizeBytes: Int64?
    public let modifiedAt: Date?

    public var id: String { name }

    /// Heuristic: does this look chat-capable? Embedding-only / reranker
    /// models cannot be called via /chat/completions. This is a capability
    /// filter, not a ranking — we surface every chat-capable model the
    /// user has, in install order.
    public var isChatCapable: Bool {
        let lower = name.lowercased()
        // Concrete capability blockers, not model preferences:
        //   embed / embedding → vector output, no chat completion
        //   rerank / reranker → cross-encoder score output, no chat
        return !lower.contains("embed") && !lower.contains("rerank")
    }
}

public actor DynamicModelLoader {

    public static let shared = DynamicModelLoader()

    public struct RecommendedLocalModel: Sendable, Codable, Identifiable {
        public let tag: String
        public let title: String
        public let family: String
        public let reason: String
        public let estimatedDiskGB: Double
        public let isDefaultFallback: Bool

        public var id: String { tag }
    }

    private let ollamaBase: URL
    private let hfBase: URL
    private let session: URLSession

    public init(
        ollamaBase: URL = URL(string: "http://127.0.0.1:11434")!,
        hfBase: URL = URL(string: "https://huggingface.co")!,
        session: URLSession = .shared
    ) {
        self.ollamaBase = ollamaBase
        self.hfBase = hfBase
        self.session = session
    }

    // MARK: - Local discovery

    /// Returns every model Ollama currently has on disk, with richer
    /// metadata than the /v1/models OpenAI shim.
    public func installedOllamaModels() async -> [InstalledOllamaModel] {
        let url = ollamaBase.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.timeoutInterval = 3

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["models"] as? [[String: Any]] else {
            return []
        }

        let iso = ISO8601DateFormatter()
        return arr.compactMap { obj -> InstalledOllamaModel? in
            guard let name = obj["name"] as? String else { return nil }
            let details = obj["details"] as? [String: Any]
            let modifiedAt = (obj["modified_at"] as? String).flatMap { iso.date(from: $0) }
            return InstalledOllamaModel(
                name: name,
                family: details?["family"] as? String,
                parameterSize: details?["parameter_size"] as? String,
                quantization: details?["quantization_level"] as? String,
                format: details?["format"] as? String,
                sizeBytes: (obj["size"] as? Int).map(Int64.init),
                modifiedAt: modifiedAt
            )
        }
    }

    /// Chat-capable installed models only. Used by the provider router
    /// so it never auto-picks an embed-only model for `/chat/completions`.
    public func installedChatModels() async -> [InstalledOllamaModel] {
        await installedOllamaModels().filter(\.isChatCapable)
    }

    // MARK: - Hardware-aware default

    /// First-run model-recommendation memory bands (total RAM in GB). These
    /// govern which Gemma/Qwen tag the daemon suggests as the default fallback
    /// when the user has no installed local models yet — i.e., the bands
    /// directly shape the new-user experience and shouldn't drift silently.
    public enum MemoryBands {
        /// Below this — pick the smallest Gemma E2B + smallest Qwen 2B.
        public static let lowMemoryGB: Double = 12
        /// Below this — Qwen routes to the 9B tier; Gemma still on E4B.
        public static let midMemoryGB: Double = 24
        /// Below this — Gemma stays on E4B; Qwen routes to the 27B tier.
        public static let highMemoryGB: Double = 48
        /// Below this — Gemma routes to 26B MoE; Qwen routes to 35B MoE.
        /// At or above, both pick the largest workstation tier.
        public static let workstationMemoryGB: Double = 96
    }

    public nonisolated func defaultFallbackModel(hardware: HardwareProfile) -> String {
        recommendedGemmaModel(hardware: hardware).tag
    }

    public nonisolated func recommendedLocalModels(hardware: HardwareProfile) -> [RecommendedLocalModel] {
        [
            recommendedGemmaModel(hardware: hardware),
            recommendedQwenModel(hardware: hardware),
            recommendedFunctionGemmaModel(),
        ]
    }

    /// Whether the hardware-aware default fallback is already on disk.
    public func defaultIsInstalled(hardware: HardwareProfile) async -> Bool {
        let installed = await installedOllamaModels().map(\.name)
        let target = defaultFallbackModel(hardware: hardware)
        return installed.contains(where: { $0.hasPrefix(target) })
    }

    public nonisolated func recommendedQwenTag(hardware: HardwareProfile) -> String {
        recommendedQwenModel(hardware: hardware).tag
    }

    private nonisolated func recommendedGemmaModel(hardware: HardwareProfile) -> RecommendedLocalModel {
        switch hardware.totalMemoryGB {
        case ..<MemoryBands.lowMemoryGB:
            return RecommendedLocalModel(
                tag: ModelDefaults.localOpenAIFallbackModelID,
                title: "Gemma 4 E2B",
                family: "Gemma 4",
                reason: "Small Gemma 4 fallback for tight memory budgets.",
                estimatedDiskGB: 7.2,
                isDefaultFallback: true
            )
        case ..<MemoryBands.highMemoryGB:
            return RecommendedLocalModel(
                tag: ModelDefaults.localOpenAIModelID,
                title: "Gemma 4 E4B",
                family: "Gemma 4",
                reason: "Default local agent for this Mac: 4B quantized Gemma 4 with 128K context.",
                estimatedDiskGB: 9.6,
                isDefaultFallback: true
            )
        case ..<MemoryBands.workstationMemoryGB:
            return RecommendedLocalModel(
                tag: "gemma4:26b",
                title: "Gemma 4 26B A4B",
                family: "Gemma 4",
                reason: "MoE workstation model for local coding and agent workflows.",
                estimatedDiskGB: 18.0,
                isDefaultFallback: true
            )
        default:
            return RecommendedLocalModel(
                tag: "gemma4:31b",
                title: "Gemma 4 31B",
                family: "Gemma 4",
                reason: "Dense Gemma 4 workstation model for maximum local quality.",
                estimatedDiskGB: 20.0,
                isDefaultFallback: true
            )
        }
    }

    private nonisolated func recommendedQwenModel(hardware: HardwareProfile) -> RecommendedLocalModel {
        switch hardware.totalMemoryGB {
        case ..<MemoryBands.lowMemoryGB:
            return RecommendedLocalModel(
                tag: "qwen3.5:2b",
                title: "Qwen 3.5 2B",
                family: "Qwen 3.5",
                reason: "Smallest current Qwen that still keeps the 256K context window.",
                estimatedDiskGB: 2.7,
                isDefaultFallback: false
            )
        case ..<MemoryBands.midMemoryGB:
            return RecommendedLocalModel(
                tag: "qwen3.5:9b",
                title: "Qwen 3.5 9B",
                family: "Qwen 3.5",
                reason: "Best Qwen fit for 16 GB Macs: 256K context, multimodal, useful for coding.",
                estimatedDiskGB: 6.6,
                isDefaultFallback: false
            )
        case ..<MemoryBands.highMemoryGB:
            return RecommendedLocalModel(
                tag: "qwen3.6:27b",
                title: "Qwen 3.6 27B",
                family: "Qwen 3.6",
                reason: "Open-weight Qwen 3.6 dense model for stronger repo-level coding.",
                estimatedDiskGB: 17.0,
                isDefaultFallback: false
            )
        case ..<MemoryBands.workstationMemoryGB:
            return RecommendedLocalModel(
                tag: "qwen3.6:35b",
                title: "Qwen 3.6 35B A3B",
                family: "Qwen 3.6",
                reason: "MoE Qwen 3.6 model tuned for agentic coding and long context.",
                estimatedDiskGB: 24.0,
                isDefaultFallback: false
            )
        default:
            return RecommendedLocalModel(
                tag: "qwen3-coder-next",
                title: "Qwen3 Coder Next",
                family: "Qwen3 Coder",
                reason: "Large coding-focused Qwen for high-memory workstations.",
                estimatedDiskGB: 52.0,
                isDefaultFallback: false
            )
        }
    }

    private nonisolated func recommendedFunctionGemmaModel() -> RecommendedLocalModel {
        RecommendedLocalModel(
                tag: ModelDefaults.phoneFunctionCallingModelID,
            title: "FunctionGemma 270M",
            family: "FunctionGemma",
            reason: "Phone-sized local model specialized for function calls and tool routing.",
            estimatedDiskGB: 0.3,
            isDefaultFallback: false
        )
    }

    // MARK: - Remote discovery (Hugging Face trending)

    public struct TrendingModel: Sendable, Codable, Identifiable {
        public let id: String           // "google/gemma-4-2b-it"
        public let downloads: Int?
        public let likes: Int?
        public let pipelineTag: String?
        public let tags: [String]
    }

    /// Live Hugging Face listing for chat-capable models, sorted by HF's
    /// own download count. No hardcoded family list — HF's ranking
    /// answers the "what's hot right now" question.
    public func trendingChatModels(limit: Int = 25) async -> [TrendingModel] {
        var components = URLComponents(
            url: hfBase.appendingPathComponent("api/models"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "pipeline_tag", value: "text-generation"),
            URLQueryItem(name: "sort",        value: "downloads"),
            URLQueryItem(name: "direction",   value: "-1"),
            URLQueryItem(name: "limit",       value: "\(limit)"),
        ]
        guard let url = components.url else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5

        guard let (data, _) = try? await session.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return arr.compactMap { obj -> TrendingModel? in
            guard let id = obj["id"] as? String else { return nil }
            return TrendingModel(
                id: id,
                downloads: obj["downloads"] as? Int,
                likes: obj["likes"] as? Int,
                pipelineTag: obj["pipeline_tag"] as? String,
                tags: obj["tags"] as? [String] ?? []
            )
        }
    }
}
