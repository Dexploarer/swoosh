// SwooshModels/ModelCatalog.swift — Local Model Catalog & Discovery
//
// Every model the user can run locally is typed, sized, and capability-tagged.
// Users pick models by ROLE (agent, judge, embedder, tts, etc.)
// The catalog filters based on their machine's capabilities.
//
// Sources:
//   1. Built-in curated list (ships with Swoosh)
//   2. Hugging Face API discovery (live)
//   3. Ollama local inventory (localhost:11434)

import Foundation

// MARK: - Model capability

/// What a model can do. A model may have multiple capabilities.
public enum ModelCapability: String, Codable, Sendable, CaseIterable {
    // ── Text ────────────────────────────────────────
    case textGeneration        // General text/reasoning
    case coding                // Code generation / SWE
    case codeCompletion        // FIM / autocomplete
    case toolCalling           // Native function calling
    case structuredOutput      // JSON / schema output
    case classification        // Sentiment, intent, routing
    case summarization         // Text summarization
    case namedEntityRecognition // NER extraction
    case questionAnswering     // Extractive QA
    case sentimentAnalysis     // Sentiment scoring
    case translation           // Dedicated translation
    case guard_                // Safety / guardrail
    case judge                 // LLM-as-judge scoring

    // ── Vision ──────────────────────────────────────
    case vision                // Image understanding / VLM
    case ocr                   // Document / text extraction
    case documentLayout        // Document structure / table parsing
    case objectDetection       // YOLO-style bounding boxes
    case imageSegmentation     // SAM-style masks
    case depthEstimation       // Monocular depth maps
    case imageClassification   // Image categorization

    // ── Audio ───────────────────────────────────────
    case speechToText          // STT / ASR
    case textToSpeech          // TTS
    case voiceCloning          // Zero-shot voice cloning
    case voiceDesign           // Create voice from text description
    case vad                   // Voice activity detection
    case diarization           // Speaker identification
    case audioSeparation       // Source separation (vocals/instruments)
    case soundEffects          // Sound effect generation

    // ── Generation ──────────────────────────────────
    case imageGeneration       // Text-to-image
    case imageEditing          // Inpainting / outpainting / style transfer
    case imageUpscaling        // Super-resolution (ESRGAN etc.)
    case videoGeneration       // Text-to-video
    case musicGeneration       // Text-to-music/audio
    case threeD                // 3D generation / point cloud

    // ── Retrieval ───────────────────────────────────
    case embedding             // Semantic vectors
    case reranking             // RAG reranker
}

// MARK: - Model size tier

/// Hardware-friendly size classification.
public enum ModelSizeTier: String, Codable, Sendable, CaseIterable, Comparable {
    case nano       // < 500M   (guardrails, VAD, classifiers)
    case micro      // 500M–1B  (judges, routers, tiny TTS)
    case small      // 1B–4B   (fast agents, autocomplete, TTS)
    case medium     // 4B–10B  (solid agents, VLMs, embeddings)
    case large      // 10B–20B (primary agent, heavy reasoning)
    case xlarge     // 20B–40B (needs 32GB+)
    case massive    // 40B+    (needs 64GB+)

    public static func < (lhs: ModelSizeTier, rhs: ModelSizeTier) -> Bool {
        let order: [ModelSizeTier] = [.nano, .micro, .small, .medium, .large, .xlarge, .massive]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    /// Estimated max memory for this tier (GB)
    public var maxMemoryGB: Double {
        switch self {
        case .nano:    return 0.5
        case .micro:   return 1.0
        case .small:   return 3.0
        case .medium:  return 7.0
        case .large:   return 12.0
        case .xlarge:  return 25.0
        case .massive: return 100.0
        }
    }
}

// MARK: - Model format

/// The serialization format / runtime required.
public enum ModelFormat: String, Codable, Sendable, CaseIterable {
    case gguf          // llama.cpp / Ollama / LM Studio
    case mlx           // Apple MLX framework
    case safetensors   // Hugging Face standard
    case coreml        // Apple Core ML
    case onnx          // ONNX Runtime
    case system        // Built into macOS (Foundation Models, AVSpeech, etc.)
    case custom        // App-specific (Draw Things, etc.)
}

// MARK: - Model source

/// Where to get the model from.
public enum ModelSource: String, Codable, Sendable, CaseIterable {
    case ollama        // ollama pull <name>
    case huggingFace   // Download from HF
    case mlxCommunity  // mlx-community on HF
    case brewFormula   // brew install
    case macAppStore   // App Store download
    case github        // git clone
    case system        // Already on device (macOS)
    case pip           // pip install
}

// MARK: - Model role

/// The job this model performs in the Swoosh agent stack.
/// A user assigns models to roles. Multiple models can share a role (fallback chain).
public enum ModelRole: String, Codable, Sendable, CaseIterable {
    case agent             // Primary reasoning / conversation
    case coder             // Code generation (may be same as agent)
    case autocomplete      // FIM code completion in editor
    case judge             // Scoring / evaluation / LLM-as-judge
    case router            // Intent classification / request routing
    case guardrail         // Safety filter
    case extractor         // Structured data extraction
    case summarizer        // Document summarization
    case embedder          // Semantic search vectors
    case reranker          // RAG quality boost
    case vision            // Image understanding
    case ocrEngine         // Document text extraction
    case objectDetector    // Bounding box detection
    case transcriber       // Speech-to-text
    case speaker           // Text-to-speech
    case imageGenerator    // Image creation
    case imageEditor       // Inpainting / editing
    case upscaler          // Super-resolution
    case videoGenerator    // Video creation
    case musicGenerator    // Music/audio creation
    case soundDesigner     // Sound effects
    case translator        // Translation
    case vadGate           // Voice activity detection
    case speakerIdentifier // Speaker diarization
    case fast              // Quick/cheap tasks (Apple Foundation Models)
    case fallback          // Cloud fallback (OpenAI, Anthropic, etc.)
}

// MARK: - Hardware profile

/// Describes the user's machine. Used to filter compatible models.
public struct HardwareProfile: Codable, Sendable {
    public let chip: String          // e.g. "Apple M4"
    public let totalMemoryGB: Double // e.g. 16.0
    public let gpuCores: Int         // e.g. 10
    public let neuralEngineCores: Int // e.g. 16
    public let osVersion: String     // e.g. "macOS 26.4"

    public init(
        chip: String,
        totalMemoryGB: Double,
        gpuCores: Int,
        neuralEngineCores: Int,
        osVersion: String
    ) {
        self.chip = chip
        self.totalMemoryGB = totalMemoryGB
        self.gpuCores = gpuCores
        self.neuralEngineCores = neuralEngineCores
        self.osVersion = osVersion
    }

    /// Usable memory for models (total minus OS overhead)
    public var usableMemoryGB: Double {
        max(totalMemoryGB - 4.0, 2.0) // Reserve ~4GB for macOS + apps
    }

    /// Maximum model size tier this hardware can run
    public var maxTier: ModelSizeTier {
        switch usableMemoryGB {
        case ..<1:   return .nano
        case ..<2:   return .micro
        case ..<5:   return .small
        case ..<9:   return .medium
        case ..<18:  return .large
        case ..<30:  return .xlarge
        default:     return .massive
        }
    }

    /// Detect the current machine's profile
    public static func detectCurrent() -> HardwareProfile {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / (1024 * 1024 * 1024)

        // Chip detection from sysctl
        var chip = "Unknown"
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            chip = String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
        }

        // GPU cores (approximate from chip name)
        let gpuCores: Int
        if chip.contains("M4 Pro") { gpuCores = 20 }
        else if chip.contains("M4 Max") { gpuCores = 40 }
        else if chip.contains("M4") { gpuCores = 10 }
        else if chip.contains("M3 Pro") { gpuCores = 18 }
        else if chip.contains("M3 Max") { gpuCores = 40 }
        else if chip.contains("M3") { gpuCores = 10 }
        else if chip.contains("M2 Pro") { gpuCores = 19 }
        else if chip.contains("M2 Max") { gpuCores = 38 }
        else if chip.contains("M2") { gpuCores = 10 }
        else if chip.contains("M1 Pro") { gpuCores = 16 }
        else if chip.contains("M1 Max") { gpuCores = 32 }
        else if chip.contains("M1") { gpuCores = 8 }
        else { gpuCores = 8 }

        let neuralEngineCores = chip.contains("M4") ? 16 : 16

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        return HardwareProfile(
            chip: chip,
            totalMemoryGB: totalGB,
            gpuCores: gpuCores,
            neuralEngineCores: neuralEngineCores,
            osVersion: osVersion
        )
    }
}

// MARK: - Catalog entry

/// A single model in the catalog. This is the core data type.
public struct CatalogEntry: Codable, Sendable, Identifiable {
    public let id: String                      // Unique ID (e.g. "qwen3-14b")
    public let name: String                    // Human name (e.g. "Qwen3 14B")
    public let family: String                  // Model family (e.g. "Qwen3")
    public let version: String                 // Version string
    public let parameterCount: String          // e.g. "14B", "0.6B", "82M"
    public let sizeTier: ModelSizeTier
    public let estimatedMemoryGB: Double       // VRAM/unified memory at Q4
    public let capabilities: Set<ModelCapability>
    public let formats: Set<ModelFormat>
    public let sources: [ModelSource]
    public let defaultRoles: Set<ModelRole>    // What this model is good at
    public let license: String                 // e.g. "Apache 2.0", "MIT"

    // Install commands per source
    public let installCommands: [ModelSource: String]

    // Metadata
    public let description: String
    public let homepage: String?
    public let huggingFaceID: String?          // e.g. "Qwen/Qwen3-14B"
    public let ollamaTag: String?              // e.g. "qwen3:14b"
    public let isCurated: Bool                 // true = ships with Swoosh catalog

    public init(
        id: String, name: String, family: String, version: String,
        parameterCount: String, sizeTier: ModelSizeTier, estimatedMemoryGB: Double,
        capabilities: Set<ModelCapability>, formats: Set<ModelFormat>,
        sources: [ModelSource], defaultRoles: Set<ModelRole>, license: String,
        installCommands: [ModelSource: String], description: String,
        homepage: String? = nil, huggingFaceID: String? = nil, ollamaTag: String? = nil,
        isCurated: Bool = true
    ) {
        self.id = id; self.name = name; self.family = family; self.version = version
        self.parameterCount = parameterCount; self.sizeTier = sizeTier
        self.estimatedMemoryGB = estimatedMemoryGB; self.capabilities = capabilities
        self.formats = formats; self.sources = sources; self.defaultRoles = defaultRoles
        self.license = license; self.installCommands = installCommands
        self.description = description; self.homepage = homepage
        self.huggingFaceID = huggingFaceID; self.ollamaTag = ollamaTag
        self.isCurated = isCurated
    }
}

// MARK: - Model catalog actor

/// The central registry of all available models.
/// Combines curated entries + live HF/Ollama discovery.
public actor ModelCatalog {
    private var entries: [String: CatalogEntry] = [:]
    private let hardware: HardwareProfile

    public init(hardware: HardwareProfile? = nil) {
        self.hardware = hardware ?? .detectCurrent()
        // Load curated catalog
        for entry in Self.curatedModels {
            entries[entry.id] = entry
        }
    }

    // MARK: - Query

    /// All models that fit this hardware
    public func compatible() -> [CatalogEntry] {
        entries.values
            .filter { $0.estimatedMemoryGB <= hardware.usableMemoryGB }
            .sorted { $0.name < $1.name }
    }

    /// Models for a specific role that fit this hardware
    public func forRole(_ role: ModelRole) -> [CatalogEntry] {
        compatible().filter { $0.defaultRoles.contains(role) }
    }

    /// Models with a specific capability
    public func withCapability(_ cap: ModelCapability) -> [CatalogEntry] {
        compatible().filter { $0.capabilities.contains(cap) }
    }

    /// Models in a specific size tier
    public func inTier(_ tier: ModelSizeTier) -> [CatalogEntry] {
        compatible().filter { $0.sizeTier == tier }
    }

    /// Models at or below a size tier
    public func atOrBelow(_ tier: ModelSizeTier) -> [CatalogEntry] {
        compatible().filter { $0.sizeTier <= tier }
    }

    /// Search by name
    public func search(_ query: String) -> [CatalogEntry] {
        let q = query.lowercased()
        return compatible().filter {
            $0.name.lowercased().contains(q) ||
            $0.family.lowercased().contains(q) ||
            $0.id.lowercased().contains(q)
        }
    }

    /// Get a specific entry
    public func get(_ id: String) -> CatalogEntry? {
        entries[id]
    }

    /// Add a discovered or custom entry
    public func register(_ entry: CatalogEntry) {
        entries[entry.id] = entry
    }

    /// Summary grouped by role
    public func summary() -> [(role: ModelRole, models: [CatalogEntry])] {
        ModelRole.allCases.compactMap { role in
            let models = forRole(role)
            return models.isEmpty ? nil : (role: role, models: models)
        }
    }
}
