// SwooshModels/ModelCatalog.swift — Local model catalog enums + HardwareProfile — 0.9T
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

// MARK: - Default roles for capabilities

extension ModelCapability {
    /// The role(s) a model with this capability defaults to. Used by
    /// discovery sources (e.g., HuggingFace) when promoting a freshly-
    /// discovered model into a `CatalogEntry` — curated entries override
    /// this with explicit `defaultRoles`.
    var defaultRoles: Set<ModelRole> {
        switch self {
        // Text
        case .textGeneration: return [.agent]
        case .coding: return [.coder]
        case .codeCompletion: return [.autocomplete]
        case .toolCalling: return [.agent]
        case .structuredOutput: return [.extractor]
        case .classification, .sentimentAnalysis: return [.router]
        case .summarization: return [.summarizer]
        case .namedEntityRecognition: return [.extractor]
        case .questionAnswering: return [.agent]
        case .translation: return [.translator]
        case .guard_: return [.guardrail]
        case .judge: return [.judge]
        // Vision
        case .vision: return [.vision]
        case .ocr, .documentLayout: return [.ocrEngine]
        case .objectDetection: return [.objectDetector]
        case .imageSegmentation: return [.vision]
        case .depthEstimation: return [.vision]
        case .imageClassification: return [.router]
        // Audio
        case .speechToText: return [.transcriber]
        case .textToSpeech, .voiceCloning, .voiceDesign: return [.speaker]
        case .vad: return [.vadGate]
        case .diarization: return [.speakerIdentifier]
        case .audioSeparation: return [.speakerIdentifier]
        case .soundEffects: return [.soundDesigner]
        // Generation
        case .imageGeneration: return [.imageGenerator]
        case .imageEditing: return [.imageEditor]
        case .imageUpscaling: return [.upscaler]
        case .videoGeneration: return [.videoGenerator]
        case .musicGeneration: return [.musicGenerator]
        case .threeD: return [.imageGenerator]
        // Retrieval
        case .embedding: return [.embedder]
        case .reranking: return [.reranker]
        }
    }
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
    case fallback          // Cloud fallback
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
