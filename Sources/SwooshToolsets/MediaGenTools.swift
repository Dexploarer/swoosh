// SwooshToolsets/MediaGenTools.swift — 0.4A Media generation tool wrappers
//
// Typed SwooshTool wrappers around SwooshImageGen + SwooshMusic. The
// registry-mounted tools are the primary permission gate (firewall +
// approval). Underlying providers also accept optional firewall/audit
// injections for defense-in-depth on direct (non-registry) calls.
//
// Output shape: media bytes are written to `~/.swoosh/media-cache/`
// (or the platform's Application Support equivalent on iOS) and the
// tool returns the file path + metadata. Inline base64 in JSON would
// bloat audit/replay payloads — see Tool.swift's `redactedPreview`.

import Foundation
import SwooshTools
import SwooshImageGen
import SwooshMusic

// ═══════════════════════════════════════════════════════════════════
// MARK: - Generate image
// ═══════════════════════════════════════════════════════════════════

public struct GenerateImageInput: Codable, Sendable {
    public let prompt: String
    public let negativePrompt: String?
    public let style: String?
    public let width: Int?
    public let height: Int?
    public let seed: UInt64?

    public init(
        prompt: String,
        negativePrompt: String? = nil,
        style: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        seed: UInt64? = nil
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.style = style
        self.width = width
        self.height = height
        self.seed = seed
    }
}

public struct GenerateImageOutput: Codable, Sendable {
    public let providerID: String
    public let path: String
    public let bytes: Int
    public let format: String
    public let usedStyle: String?

    public init(providerID: String, path: String, bytes: Int, format: String, usedStyle: String?) {
        self.providerID = providerID
        self.path = path
        self.bytes = bytes
        self.format = format
        self.usedStyle = usedStyle
    }
}

public struct GenerateImageTool: SwooshTool {
    public typealias Input = GenerateImageInput
    public typealias Output = GenerateImageOutput
    public static let name: ToolName = "media.generate_image"
    public static let displayName = "Generate Image"
    public static let description = "Generate an image from a prompt. Local Apple Image Playground or cloud (OpenAI)."
    public static let permission = SwooshPermission.imageGenerate
    public static let risk = ToolRisk.medium
    public static let approval = ApprovalPolicy.askFirstTime
    public static let toolset = ToolsetID.mediaGen

    let provider: any ImageGenProviding
    let cacheDir: URL

    public init(provider: any ImageGenProviding, cacheDir: URL = MediaCacheDir.default()) {
        self.provider = provider
        self.cacheDir = cacheDir
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let request = ImageGenRequest(
            prompt: input.prompt,
            negativePrompt: input.negativePrompt,
            style: input.style.map { ImageGenStyle(id: $0, displayName: $0) },
            width: input.width ?? 1024,
            height: input.height ?? 1024,
            seed: input.seed ?? 0
        )
        let result = try await provider.generate(request)
        let path = try MediaCacheDir.write(
            result.pngData,
            extension: "png",
            in: cacheDir
        )
        return GenerateImageOutput(
            providerID: result.providerID,
            path: path.path,
            bytes: result.pngData.count,
            format: "png",
            usedStyle: result.usedStyle
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Generate video
// ═══════════════════════════════════════════════════════════════════

public struct GenerateVideoInput: Codable, Sendable {
    public let prompt: String
    public let negativePrompt: String?
    public let modelID: String
    public let durationSeconds: Double?
    public let width: Int?
    public let height: Int?
    public let seed: UInt64?

    public init(
        prompt: String,
        negativePrompt: String? = nil,
        modelID: String,
        durationSeconds: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        seed: UInt64? = nil
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.modelID = modelID
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.seed = seed
    }
}

public struct GenerateVideoOutput: Codable, Sendable {
    public let providerID: String
    public let modelID: String
    public let path: String
    public let mimeType: String
    public let bytes: Int

    public init(providerID: String, modelID: String, path: String, mimeType: String, bytes: Int) {
        self.providerID = providerID
        self.modelID = modelID
        self.path = path
        self.mimeType = mimeType
        self.bytes = bytes
    }
}

public struct GenerateVideoTool: SwooshTool {
    public typealias Input = GenerateVideoInput
    public typealias Output = GenerateVideoOutput
    public static let name: ToolName = "media.generate_video"
    public static let displayName = "Generate Video"
    public static let description = "Generate a video from a prompt via FAL.ai (Veo 3, Kling, Hunyuan, Luma)."
    public static let permission = SwooshPermission.videoGenerate
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.mediaGen

    let provider: any VideoGenProviding
    let cacheDir: URL

    public init(provider: any VideoGenProviding, cacheDir: URL = MediaCacheDir.default()) {
        self.provider = provider
        self.cacheDir = cacheDir
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let request = VideoGenRequest(
            prompt: input.prompt,
            negativePrompt: input.negativePrompt,
            modelID: input.modelID,
            durationSeconds: input.durationSeconds ?? 5,
            width: input.width ?? 1280,
            height: input.height ?? 720,
            seed: input.seed ?? 0
        )
        let result = try await provider.generate(request)
        let ext = MediaCacheDir.fileExtension(forMime: result.mimeType, fallback: "mp4")
        let path = try MediaCacheDir.write(
            result.videoData,
            extension: ext,
            in: cacheDir
        )
        return GenerateVideoOutput(
            providerID: result.providerID,
            modelID: result.modelID,
            path: path.path,
            mimeType: result.mimeType,
            bytes: result.videoData.count
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Generate 3D
// ═══════════════════════════════════════════════════════════════════

public struct Generate3DInput: Codable, Sendable {
    public let prompt: String?
    public let modelID: String
    public let outputFormat: String?
    public let seed: UInt64?

    public init(prompt: String? = nil, modelID: String, outputFormat: String? = nil, seed: UInt64? = nil) {
        self.prompt = prompt
        self.modelID = modelID
        self.outputFormat = outputFormat
        self.seed = seed
    }
}

public struct Generate3DOutput: Codable, Sendable {
    public let providerID: String
    public let modelID: String
    public let path: String
    public let format: String
    public let bytes: Int

    public init(providerID: String, modelID: String, path: String, format: String, bytes: Int) {
        self.providerID = providerID
        self.modelID = modelID
        self.path = path
        self.format = format
        self.bytes = bytes
    }
}

public struct Generate3DTool: SwooshTool {
    public typealias Input = Generate3DInput
    public typealias Output = Generate3DOutput
    public static let name: ToolName = "media.generate_3d"
    public static let displayName = "Generate 3D Model"
    public static let description = "Generate a 3D asset from a prompt or image via FAL.ai (Tripo3D, Trellis, TripoSR, Hunyuan3D)."
    public static let permission = SwooshPermission.threeDGenerate
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.mediaGen

    let provider: any ThreeDGenProviding
    let cacheDir: URL

    public init(provider: any ThreeDGenProviding, cacheDir: URL = MediaCacheDir.default()) {
        self.provider = provider
        self.cacheDir = cacheDir
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let format = input.outputFormat.flatMap(ThreeDOutputFormat.init(rawValue:)) ?? .glb
        let request = ThreeDGenRequest(
            prompt: input.prompt,
            modelID: input.modelID,
            outputFormat: format,
            seed: input.seed ?? 0
        )
        let result = try await provider.generate(request)
        let path = try MediaCacheDir.write(
            result.modelData,
            extension: result.format.rawValue,
            in: cacheDir
        )
        return Generate3DOutput(
            providerID: result.providerID,
            modelID: result.modelID,
            path: path.path,
            format: result.format.rawValue,
            bytes: result.modelData.count
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Generate music
// ═══════════════════════════════════════════════════════════════════

public struct GenerateMusicInput: Codable, Sendable {
    public let prompt: String
    public let model: String?
    public let durationSeconds: Double?
    public let style: String?
    public let lyrics: String?
    public let instrumentalOnly: Bool?

    public init(
        prompt: String,
        model: String? = nil,
        durationSeconds: Double? = nil,
        style: String? = nil,
        lyrics: String? = nil,
        instrumentalOnly: Bool? = nil
    ) {
        self.prompt = prompt
        self.model = model
        self.durationSeconds = durationSeconds
        self.style = style
        self.lyrics = lyrics
        self.instrumentalOnly = instrumentalOnly
    }
}

public struct GenerateMusicOutput: Codable, Sendable {
    public let providerID: String
    public let modelID: String
    public let path: String
    public let mimeType: String
    public let bytes: Int
    public let durationSeconds: Double?

    public init(
        providerID: String,
        modelID: String,
        path: String,
        mimeType: String,
        bytes: Int,
        durationSeconds: Double?
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.path = path
        self.mimeType = mimeType
        self.bytes = bytes
        self.durationSeconds = durationSeconds
    }
}

public struct GenerateMusicTool: SwooshTool {
    public typealias Input = GenerateMusicInput
    public typealias Output = GenerateMusicOutput
    public static let name: ToolName = "media.generate_music"
    public static let displayName = "Generate Music"
    public static let description = "Generate a music clip from a prompt via Suno, ElevenLabs Music, or Stable Audio."
    public static let permission = SwooshPermission.musicGenerate
    public static let risk = ToolRisk.high
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.mediaGen

    let provider: any MusicProviding
    let cacheDir: URL
    let downloader: any AudioDownloading

    public init(
        provider: any MusicProviding,
        cacheDir: URL = MediaCacheDir.default(),
        downloader: any AudioDownloading = URLSessionAudioDownloader()
    ) {
        self.provider = provider
        self.cacheDir = cacheDir
        self.downloader = downloader
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let request = MusicRequest(
            prompt: input.prompt,
            model: input.model,
            durationSeconds: input.durationSeconds,
            style: input.style,
            lyrics: input.lyrics,
            instrumentalOnly: input.instrumentalOnly ?? false
        )
        let job = try await provider.generate(request)
        let result = try await job.result
        // Unify with image/video/3D: stage the bytes in MediaCacheDir
        // regardless of whether the provider returned a remote CDN URL
        // (Suno) or a local temp file (ElevenLabs, Stable Audio).
        let bytes = try await downloader.bytes(from: result.audioURL)
        let ext = MediaCacheDir.fileExtension(forMime: result.mimeType, fallback: "mp3")
        let cached = try MediaCacheDir.write(bytes, extension: ext, in: cacheDir)
        return GenerateMusicOutput(
            providerID: job.id,
            modelID: result.modelUsed,
            path: cached.path,
            mimeType: result.mimeType,
            bytes: bytes.count,
            durationSeconds: result.durationSeconds
        )
    }
}
