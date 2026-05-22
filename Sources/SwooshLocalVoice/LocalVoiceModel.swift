// SwooshLocalVoice/LocalVoiceModel.swift — 0.9R On-device voice model schema
//
// One struct describing a downloadable on-device TTS model. Mirrors
// `SwooshLocalLLM.LiteRTModel` so the device-policy picker, downloader,
// and UI can reuse the same patterns.
//
// The schema deliberately does NOT bind to a specific inference runtime —
// `engineKind` tells callers which engine wrapper (ONNX Runtime, MLX,
// CoreML, or the temporary Apple fallback) drives the weights.

import Foundation

public struct LocalVoiceModel: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let family: String          // "Kokoro" | "OmniVoice"
    public let downloadURL: URL
    public let estimatedBytes: Int64
    public let parameters: String      // "82M" | "600M"
    public let license: String
    public let engineKind: EngineKind
    public let supportsVoiceCloning: Bool
    public let languageCount: Int      // 1 = English-only; 600 = OmniVoice
    public let defaultSampleRate: Int  // Hz (e.g. 24000 for Kokoro, 22050 for OmniVoice)

    /// Which runtime is expected to load these weights. The current
    /// `LocalVoiceEngine` falls back to AVSpeechSynthesizer when the
    /// corresponding runtime isn't compiled in; tests assert that every
    /// catalog entry has a known kind so the picker never returns junk.
    public enum EngineKind: String, Codable, Sendable, CaseIterable {
        /// Ports exported to ONNX (Kokoro, CosyVoice2). Engine path will
        /// load via the onnxruntime-swift-package-manager package when
        /// it's added as a dependency.
        case onnx
        /// MLX-Audio ports (Apple-silicon optimised, Mac-first).
        case mlx
        /// CoreML mlmodelc bundles compiled from the upstream PyTorch.
        case coreml
        /// Apple AVSpeechSynthesizer fallback — used when no real engine
        /// is wired yet so the audio loop is testable end-to-end.
        case appleFallback
    }

    public init(
        id: String,
        displayName: String,
        family: String,
        downloadURL: URL,
        estimatedBytes: Int64,
        parameters: String,
        license: String,
        engineKind: EngineKind,
        supportsVoiceCloning: Bool,
        languageCount: Int,
        defaultSampleRate: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.downloadURL = downloadURL
        self.estimatedBytes = estimatedBytes
        self.parameters = parameters
        self.license = license
        self.engineKind = engineKind
        self.supportsVoiceCloning = supportsVoiceCloning
        self.languageCount = languageCount
        self.defaultSampleRate = defaultSampleRate
    }
}
