#if os(iOS)

// SwooshLocalLLM/LiteRTModelCatalog.swift — 0.9R On-device model catalog
//
// Built-in catalog of LiteRT-LM `.litertlm` models. Each entry records
// the canonical download URL (HuggingFace), expected byte size for
// progress UI, parameter count, multimodal capabilities, and whether
// the model needs the iOS `com.apple.developer.kernel.extended-virtual-
// addressing` entitlement (models above ~2GB do).
//
// Default = Gemma 3n E2B Int4 — 1.3GB, no entitlement required, runs on
// any iPhone 15 Pro+ / M-series Mac.

import Foundation

public struct LiteRTModel: Codable, Sendable, Identifiable, Hashable {
    public let id: String              // e.g. "gemma-3n-E2B-it-int4"
    public let displayName: String     // e.g. "Gemma 3n E2B (4-bit)"
    public let family: String          // e.g. "Gemma"
    public let downloadURL: URL
    public let estimatedBytes: Int64   // for progress UI
    public let parameters: String      // "2B" / "4B"
    public let contextWindow: Int
    public let supportsVision: Bool
    public let supportsAudio: Bool
    /// True when the model is >2GB and needs
    /// `com.apple.developer.kernel.extended-virtual-addressing`. Paid
    /// developer account required; runtime check happens at load time.
    public let requiresExtendedAddressing: Bool

    public init(
        id: String,
        displayName: String,
        family: String,
        downloadURL: URL,
        estimatedBytes: Int64,
        parameters: String,
        contextWindow: Int,
        supportsVision: Bool,
        supportsAudio: Bool,
        requiresExtendedAddressing: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.downloadURL = downloadURL
        self.estimatedBytes = estimatedBytes
        self.parameters = parameters
        self.contextWindow = contextWindow
        self.supportsVision = supportsVision
        self.supportsAudio = supportsAudio
        self.requiresExtendedAddressing = requiresExtendedAddressing
    }
}

public enum LiteRTModelCatalog {

    /// Default on-device model. Picked for the broadest install base —
    /// ~1.3 GB, no entitlement, works on iPhone 15 Pro+ and any M-series Mac.
    public static let defaultModel: LiteRTModel = gemma3nE2BInt4

    public static let gemma3nE2BInt4 = LiteRTModel(
        id: "gemma-3n-E2B-it-int4",
        displayName: "Gemma 3n E2B (Int4)",
        family: "Gemma",
        downloadURL: URL(string: "https://huggingface.co/litert-community/Gemma-3n-E2B-it-LiteRT-LM/resolve/main/gemma-3n-E2B-it-int4.litertlm")!,
        estimatedBytes: 1_320_000_000,
        parameters: "2B",
        contextWindow: 32_768,
        supportsVision: false,
        supportsAudio: false,
        requiresExtendedAddressing: false
    )

    public static let gemma4E2B = LiteRTModel(
        id: "gemma-4-E2B-it",
        displayName: "Gemma 4 E2B (Multimodal)",
        family: "Gemma",
        downloadURL: URL(string: "https://huggingface.co/litert-community/Gemma-4-E2B-it-LiteRT-LM/resolve/main/gemma-4-E2B-it.litertlm")!,
        estimatedBytes: 2_580_000_000,
        parameters: "2B",
        contextWindow: 32_768,
        supportsVision: true,
        supportsAudio: true,
        requiresExtendedAddressing: true
    )

    public static let gemma4E4B = LiteRTModel(
        id: "gemma-4-E4B-it",
        displayName: "Gemma 4 E4B (Higher Quality)",
        family: "Gemma",
        downloadURL: URL(string: "https://huggingface.co/litert-community/Gemma-4-E4B-it-LiteRT-LM/resolve/main/gemma-4-E4B-it.litertlm")!,
        estimatedBytes: 3_650_000_000,
        parameters: "4B",
        contextWindow: 32_768,
        supportsVision: true,
        supportsAudio: true,
        requiresExtendedAddressing: true
    )

    /// All built-in models, in default-first order.
    public static let all: [LiteRTModel] = [
        gemma3nE2BInt4,
        gemma4E2B,
        gemma4E4B,
    ]

    public static func model(id: String) -> LiteRTModel? {
        all.first(where: { $0.id == id })
    }
}

#endif
