// SwooshImageGen/VideoGenProviding.swift
// Version: 0.9R
//
// Text/image-to-video provider protocol. Cloud-only today — local video
// generation on a single Mac (CogVideoX, HunyuanVideo) is still impractical
// for most users, so the router defers to FAL/Replicate. Local executors
// can be added later by conforming to the same protocol.

import Foundation

public protocol VideoGenProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    func supportedModels() async -> [VideoGenModel]
    func generate(_ request: VideoGenRequest) async throws -> VideoGenResult
}

public struct VideoGenRequest: Sendable {
    public let prompt: String
    public let negativePrompt: String?
    /// Optional first-frame seed image (PNG bytes). Drives image-to-video.
    public let imagePNG: Data?
    /// Provider-specific model identifier (e.g. `fal-ai/veo3`).
    public let modelID: String
    public let durationSeconds: Double
    public let width: Int
    public let height: Int
    public let seed: UInt64

    public init(
        prompt: String,
        negativePrompt: String? = nil,
        imagePNG: Data? = nil,
        modelID: String,
        durationSeconds: Double = 5,
        width: Int = 1280,
        height: Int = 720,
        seed: UInt64 = 0
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.imagePNG = imagePNG
        self.modelID = modelID
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.seed = seed
    }
}

public struct VideoGenModel: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let supportsImageInput: Bool
    public let maxDurationSeconds: Double

    public init(id: String, displayName: String, supportsImageInput: Bool, maxDurationSeconds: Double) {
        self.id = id
        self.displayName = displayName
        self.supportsImageInput = supportsImageInput
        self.maxDurationSeconds = maxDurationSeconds
    }
}

public struct VideoGenResult: Sendable {
    /// MP4-encoded video bytes (or other container; check mimeType).
    public let videoData: Data
    public let mimeType: String
    public let providerID: String
    public let modelID: String

    public init(videoData: Data, mimeType: String, providerID: String, modelID: String) {
        self.videoData = videoData
        self.mimeType = mimeType
        self.providerID = providerID
        self.modelID = modelID
    }
}

public enum VideoGenError: Error, CustomStringConvertible, Sendable {
    case missingAPIKey(String)
    case unsupportedModel(String)
    case generationFailed(String)
    case queueTimeout

    public var description: String {
        switch self {
        case .missingAPIKey(let p):    return "Missing API key for \(p)."
        case .unsupportedModel(let m): return "Model \(m) is not supported by this provider."
        case .generationFailed(let m): return "Video generation failed: \(m)"
        case .queueTimeout:            return "Video generation timed out in the cloud queue."
        }
    }
}
