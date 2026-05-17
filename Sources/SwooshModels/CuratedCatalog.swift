// SwooshModels/CuratedCatalog.swift — Built-in model catalog
// Ships with Swoosh. Covers all modalities + micro models for judges/routers.

import Foundation

extension ModelCatalog {

    // MARK: - Helper

    private static func entry(
        _ id: String, _ name: String, family: String, params: String,
        tier: ModelSizeTier, mem: Double, caps: Set<ModelCapability>,
        roles: Set<ModelRole>, license: String, desc: String,
        ollama: String? = nil, hf: String? = nil,
        formats: Set<ModelFormat> = [.gguf, .mlx],
        sources: [ModelSource] = [.ollama],
        install: [ModelSource: String] = [:]
    ) -> CatalogEntry {
        CatalogEntry(
            id: id, name: name, family: family, version: "latest",
            parameterCount: params, sizeTier: tier, estimatedMemoryGB: mem,
            capabilities: caps, formats: formats, sources: sources,
            defaultRoles: roles, license: license,
            installCommands: install.isEmpty ? (ollama.map { [.ollama: "ollama pull \($0)"] } ?? [:]) : install,
            description: desc, huggingFaceID: hf, ollamaTag: ollama
        )
    }

    // MARK: - Full curated list

    static let curatedModels: [CatalogEntry] = textModels + codingModels + visionModels
        + sttModels + ttsModels + imageGenModels + embeddingModels
        + rerankerModels + microModels + systemModels

    // ── Text / Reasoning ────────────────────────────────────────────

    static let textModels: [CatalogEntry] = [
        entry("qwen3-14b", "Qwen3 14B", family: "Qwen3", params: "14B",
              tier: .large, mem: 9.0, caps: [.textGeneration, .coding, .toolCalling, .structuredOutput, .translation],
              roles: [.agent, .coder, .translator], license: "Apache 2.0",
              desc: "Best all-rounder for 16GB. Native tool calling.", ollama: "qwen3:14b"),
        entry("qwen3-8b", "Qwen3 8B", family: "Qwen3", params: "8B",
              tier: .medium, mem: 5.5, caps: [.textGeneration, .coding, .toolCalling, .structuredOutput],
              roles: [.agent, .coder], license: "Apache 2.0",
              desc: "Lighter agent, leaves room for TTS/STT.", ollama: "qwen3:8b"),
        entry("qwen3-4b", "Qwen3 4B", family: "Qwen3", params: "4B",
              tier: .small, mem: 3.0, caps: [.textGeneration, .coding, .toolCalling],
              roles: [.agent], license: "Apache 2.0",
              desc: "Fast small agent.", ollama: "qwen3:4b"),
        entry("qwen3-1.7b", "Qwen3 1.7B", family: "Qwen3", params: "1.7B",
              tier: .small, mem: 1.5, caps: [.textGeneration, .toolCalling],
              roles: [.agent, .router], license: "Apache 2.0",
              desc: "Ultra-light agent or router.", ollama: "qwen3:1.7b"),
        entry("gemma4-e4b", "Gemma 4 E4B", family: "Gemma", params: "4B",
              tier: .small, mem: 3.0, caps: [.textGeneration, .coding],
              roles: [.agent], license: "Apache 2.0",
              desc: "Google's efficiency champ.", ollama: "gemma3:4b"),
        entry("gemma3-12b", "Gemma 3 12B", family: "Gemma", params: "12B",
              tier: .large, mem: 8.0, caps: [.textGeneration, .coding, .vision],
              roles: [.agent, .vision], license: "Apache 2.0",
              desc: "Strong reasoning, multimodal.", ollama: "gemma3:12b"),
        entry("llama3.1-8b", "Llama 3.1 8B", family: "Llama", params: "8B",
              tier: .medium, mem: 5.0, caps: [.textGeneration, .coding, .toolCalling],
              roles: [.agent, .coder], license: "Community",
              desc: "Solid baseline.", ollama: "llama3.1:8b"),
        entry("phi4-mini", "Phi-4 Mini", family: "Phi", params: "3.8B",
              tier: .small, mem: 2.5, caps: [.textGeneration, .coding, .structuredOutput],
              roles: [.agent, .extractor], license: "MIT",
              desc: "Microsoft. Great reasoning for size.", ollama: "phi4-mini"),
        entry("deepseek-r1-8b", "DeepSeek-R1 8B", family: "DeepSeek", params: "8B",
              tier: .medium, mem: 5.0, caps: [.textGeneration],
              roles: [.agent, .judge], license: "MIT",
              desc: "Best chain-of-thought reasoning.", ollama: "deepseek-r1:8b"),
    ]

    // ── Coding / Autocomplete ───────────────────────────────────────

    static let codingModels: [CatalogEntry] = [
        entry("codestral-25", "Codestral 25.12", family: "Codestral", params: "7B",
              tier: .medium, mem: 5.0, caps: [.coding, .codeCompletion],
              roles: [.autocomplete, .coder], license: "Custom",
              desc: "Gold standard for FIM autocomplete.", ollama: "codestral"),
        entry("qwen3.5-0.8b", "Qwen 3.5 0.8B", family: "Qwen", params: "0.8B",
              tier: .micro, mem: 0.5, caps: [.textGeneration, .codeCompletion],
              roles: [.autocomplete, .extractor], license: "Apache 2.0",
              desc: "Tiny, 262K context, instant FIM.", ollama: "qwen3.5:0.8b"),
    ]

    // ── Vision / VLM ────────────────────────────────────────────────

    static let visionModels: [CatalogEntry] = [
        entry("qwen2.5-vl-7b", "Qwen2.5-VL 7B", family: "Qwen", params: "7B",
              tier: .medium, mem: 5.0, caps: [.vision, .ocr, .textGeneration],
              roles: [.vision, .ocrEngine], license: "Apache 2.0",
              desc: "Image reasoning, OCR 32+ langs, UI nav.", ollama: "qwen2.5-vl:7b"),
        entry("glm-ocr-0.9b", "GLM-OCR 0.9B", family: "GLM", params: "0.9B",
              tier: .micro, mem: 0.6, caps: [.ocr],
              roles: [.ocrEngine], license: "MIT",
              desc: "Best-in-class document OCR, tiny.", ollama: "glm-ocr"),
        entry("gemma3-4b-vision", "Gemma 3 4B Vision", family: "Gemma", params: "4B",
              tier: .small, mem: 3.0, caps: [.vision, .ocr, .textGeneration],
              roles: [.vision], license: "Apache 2.0",
              desc: "Lightweight vision.", ollama: "gemma3:4b"),
    ]

    // ── Speech-to-Text ──────────────────────────────────────────────

    static let sttModels: [CatalogEntry] = [
        entry("whisper-large-v3", "Whisper Large V3", family: "Whisper", params: "1.5B",
              tier: .small, mem: 1.5, caps: [.speechToText],
              roles: [.transcriber], license: "MIT",
              desc: "Best multilingual STT. 99+ languages.",
              formats: [.gguf, .coreml], sources: [.brewFormula, .github],
              install: [.brewFormula: "brew install whisper-cpp"]),
        entry("whisper-small", "Whisper Small", family: "Whisper", params: "244M",
              tier: .nano, mem: 0.5, caps: [.speechToText],
              roles: [.transcriber], license: "MIT",
              desc: "Lightweight STT. Great for voice chat.",
              formats: [.gguf], sources: [.brewFormula],
              install: [.brewFormula: "brew install whisper-cpp"]),
        entry("moonshine", "Moonshine", family: "Moonshine", params: "245M",
              tier: .nano, mem: 0.3, caps: [.speechToText],
              roles: [.transcriber], license: "MIT",
              desc: "Ultra-efficient English STT. 50x real-time.",
              sources: [.pip], install: [.pip: "pip install moonshine"]),
    ]

    // ── Text-to-Speech ──────────────────────────────────────────────

    static let ttsModels: [CatalogEntry] = [
        entry("omnivoice", "OmniVoice", family: "OmniVoice", params: "0.6B",
              tier: .micro, mem: 0.5, caps: [.textToSpeech, .voiceCloning, .voiceDesign],
              roles: [.speaker], license: "Apache 2.0",
              desc: "600+ languages. Voice design from text. 40x real-time.",
              sources: [.pip], install: [.pip: "pip install git+https://github.com/ailuntx/OmniVoice-MLX.git"]),
        entry("orpheus-3b", "Orpheus 3B", family: "Orpheus", params: "3B",
              tier: .small, mem: 2.0, caps: [.textToSpeech, .voiceCloning],
              roles: [.speaker], license: "Apache 2.0",
              desc: "ElevenLabs-quality. <laugh> <whisper> <sigh> emotions.",
              sources: [.github], install: [.github: "git clone https://github.com/isaiahbjork/orpheus-tts-local"]),
        entry("chatterbox-turbo", "Chatterbox-Turbo", family: "Chatterbox", params: "350M",
              tier: .nano, mem: 0.3, caps: [.textToSpeech, .voiceCloning],
              roles: [.speaker], license: "MIT",
              desc: "Fastest TTS. One-step decode. MLX native.",
              sources: [.pip], install: [.pip: "pip install mlx-audio"]),
        entry("kokoro-82m", "Kokoro 82M", family: "Kokoro", params: "82M",
              tier: .nano, mem: 0.05, caps: [.textToSpeech],
              roles: [.speaker], license: "Apache 2.0",
              desc: "Tiniest high-quality TTS. MOS 4.2 at 50MB.",
              sources: [.pip], install: [.pip: "pip install mlx-audio"]),
        entry("dia-1.6b", "Dia 1.6B", family: "Dia", params: "1.6B",
              tier: .small, mem: 1.0, caps: [.textToSpeech, .voiceCloning],
              roles: [.speaker], license: "Apache 2.0",
              desc: "Multi-speaker dialogue. [S1]/[S2] tags.",
              sources: [.pip], install: [.pip: "pip install mlx-audio"]),
        entry("qwen3-tts", "Qwen3-TTS", family: "Qwen", params: "0.6B",
              tier: .micro, mem: 0.5, caps: [.textToSpeech, .voiceCloning],
              roles: [.speaker], license: "Apache 2.0",
              desc: "10 languages. Instructable tone. 3s voice clone.",
              sources: [.pip], install: [.pip: "pip install mlx-audio"]),
    ]

    // ── Image Generation ────────────────────────────────────────────

    static let imageGenModels: [CatalogEntry] = [
        entry("flux2-klein-4b", "FLUX.2 Klein 4B", family: "FLUX", params: "4B",
              tier: .small, mem: 3.0, caps: [.imageGeneration],
              roles: [.imageGenerator], license: "Apache 2.0",
              desc: "Fast image gen. Fits 16GB.",
              sources: [.macAppStore], install: [.macAppStore: "Draw Things (free)"]),
        entry("sd35-medium", "SD 3.5 Medium", family: "StableDiffusion", params: "2.5B",
              tier: .small, mem: 2.0, caps: [.imageGeneration],
              roles: [.imageGenerator], license: "Stability",
              desc: "Good quality. Huge LoRA ecosystem.",
              sources: [.macAppStore], install: [.macAppStore: "Draw Things (free)"]),
    ]

    // ── Embeddings ──────────────────────────────────────────────────

    static let embeddingModels: [CatalogEntry] = [
        entry("nomic-embed-v2", "Nomic Embed v2", family: "Nomic", params: "137M",
              tier: .nano, mem: 0.3, caps: [.embedding],
              roles: [.embedder], license: "Apache 2.0",
              desc: "Tiny, fast. Runs alongside everything.", ollama: "nomic-embed-text"),
        entry("bge-m3", "BGE-M3", family: "BGE", params: "350M",
              tier: .nano, mem: 0.7, caps: [.embedding],
              roles: [.embedder], license: "MIT",
              desc: "Dense + sparse + ColBERT in one model.", ollama: "bge-m3"),
    ]

    // ── Rerankers ───────────────────────────────────────────────────

    static let rerankerModels: [CatalogEntry] = [
        entry("bge-reranker-v2", "BGE Reranker v2-m3", family: "BGE", params: "350M",
              tier: .nano, mem: 0.7, caps: [.reranking],
              roles: [.reranker], license: "Apache 2.0",
              desc: "Standard RAG reranker. 100+ languages.",
              sources: [.huggingFace], install: [.huggingFace: "huggingface-cli download BAAI/bge-reranker-v2-m3"]),
    ]

    // ── Micro Models (Judges, Routers, Guards) ──────────────────────

    static let microModels: [CatalogEntry] = [
        entry("qwen3-0.6b", "Qwen3 0.6B", family: "Qwen3", params: "0.6B",
              tier: .micro, mem: 0.5, caps: [.textGeneration, .classification, .structuredOutput],
              roles: [.judge, .router, .extractor], license: "Apache 2.0",
              desc: "Thinking/non-thinking modes. Judge, route, extract.", ollama: "qwen3:0.6b"),
        entry("gemma3-1b", "Gemma 3 1B", family: "Gemma", params: "1B",
              tier: .micro, mem: 0.7, caps: [.textGeneration, .classification],
              roles: [.judge, .router], license: "Apache 2.0",
              desc: "Google's 1B. Strong reasoning floor.", ollama: "gemma3:1b"),
        entry("llama3.2-1b", "Llama 3.2 1B", family: "Llama", params: "1B",
              tier: .micro, mem: 0.7, caps: [.textGeneration, .classification],
              roles: [.judge, .router], license: "Community",
              desc: "Meta's 1B. Widely supported everywhere.", ollama: "llama3.2:1b"),
        entry("gliguard-0.3b", "GLiGuard 0.3B", family: "GLiGuard", params: "0.3B",
              tier: .nano, mem: 0.2, caps: [.guard_, .classification],
              roles: [.guardrail], license: "Apache 2.0",
              desc: "Purpose-built safety guardrail. <100ms.",
              sources: [.huggingFace], install: [.huggingFace: "huggingface-cli download gliclass/GLiGuard-0.3B"]),
        entry("silero-vad", "Silero VAD", family: "Silero", params: "2M",
              tier: .nano, mem: 0.002, caps: [.vad],
              roles: [.vadGate], license: "MIT",
              desc: "Voice activity detection. <1ms per chunk.",
              formats: [.onnx], sources: [.pip], install: [.pip: "pip install silero-vad"]),
    ]

    // ── System Models (macOS built-in) ──────────────────────────────

    static let systemModels: [CatalogEntry] = [
        entry("apple-fm", "Apple Foundation Models", family: "Apple", params: "~3B",
              tier: .small, mem: 0.0, caps: [.textGeneration, .toolCalling, .structuredOutput],
              roles: [.fast, .extractor], license: "System",
              desc: "Built into macOS 26. Zero memory. @Generable.",
              formats: [.system], sources: [.system], install: [:]),
        entry("macos-personal-voice", "macOS Personal Voice", family: "Apple", params: "N/A",
              tier: .nano, mem: 0.0, caps: [.textToSpeech],
              roles: [.speaker], license: "System",
              desc: "User's own voice. 10 phrases to train.",
              formats: [.system], sources: [.system], install: [:]),
        entry("macos-speech", "macOS Dictation", family: "Apple", params: "N/A",
              tier: .nano, mem: 0.0, caps: [.speechToText],
              roles: [.transcriber], license: "System",
              desc: "SFSpeechRecognizer. Zero setup.",
              formats: [.system], sources: [.system], install: [:]),
    ]
}
