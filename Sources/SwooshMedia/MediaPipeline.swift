// SwooshMedia/MediaPipeline.swift — Multi-modal media capabilities
//
// Hermes-inspired media pipeline: image gen, TTS, STT, vision analysis,
// and voice mode. Routes to local (MLX) or remote (API) backends.

import Foundation

// ═══════════════════════════════════════════════════════════════════
// MARK: - Media capability protocol
// ═══════════════════════════════════════════════════════════════════

public protocol MediaCapability: Sendable {
    var capabilityID: String { get }
    var displayName: String { get }
    var isAvailable: Bool { get async }
    func execute(_ request: MediaRequest) async throws -> MediaResult
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Media request / result
// ═══════════════════════════════════════════════════════════════════

public enum MediaRequest: Sendable {
    case generateImage(prompt: String, size: ImageSize, style: ImageStyle)
    case textToSpeech(text: String, voice: String?)
    case speechToText(audioData: Data, language: String?)
    case analyzeImage(imageData: Data, prompt: String?)
    case analyzeVideo(videoURL: URL, prompt: String?)
    case screenshot(url: URL?)
}

public enum MediaResult: Sendable {
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case text(String)
    case analysis(ImageAnalysis)
}

public struct ImageSize: Codable, Sendable {
    public let width: Int; public let height: Int
    public static let small = ImageSize(width: 256, height: 256)
    public static let medium = ImageSize(width: 512, height: 512)
    public static let large = ImageSize(width: 1024, height: 1024)
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public enum ImageStyle: String, Codable, Sendable {
    case natural, vivid, artistic, photographic, sketch
}

public struct ImageAnalysis: Codable, Sendable {
    public let description: String
    public let labels: [String]
    public let confidence: Double
    public let objects: [DetectedObject]
    public init(description: String, labels: [String] = [], confidence: Double = 0, objects: [DetectedObject] = []) {
        self.description = description; self.labels = labels; self.confidence = confidence; self.objects = objects
    }
}

public struct DetectedObject: Codable, Sendable {
    public let label: String; public let confidence: Double
    public let x: Double; public let y: Double; public let width: Double; public let height: Double
    public init(label: String, confidence: Double = 0, x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        self.label = label; self.confidence = confidence; self.x = x; self.y = y; self.width = width; self.height = height
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Media router
// ═══════════════════════════════════════════════════════════════════

/// Routes media requests to available capabilities.
public actor MediaRouter {
    private var capabilities: [String: any MediaCapability] = [:]

    public init() {}

    public func register(_ capability: any MediaCapability) {
        capabilities[capability.capabilityID] = capability
    }

    public func execute(_ request: MediaRequest) async throws -> MediaResult {
        let targetID = targetCapability(for: request)
        guard let cap = capabilities[targetID], await cap.isAvailable else {
            throw MediaError.capabilityNotAvailable(targetID)
        }
        return try await cap.execute(request)
    }

    public func available() async -> [String] {
        var result: [String] = []
        for (id, cap) in capabilities {
            if await cap.isAvailable { result.append(id) }
        }
        return result
    }

    private func targetCapability(for request: MediaRequest) -> String {
        switch request {
        case .generateImage: return "image.generate"
        case .textToSpeech: return "audio.tts"
        case .speechToText: return "audio.stt"
        case .analyzeImage: return "vision.analyze"
        case .analyzeVideo: return "video.analyze"
        case .screenshot: return "browser.screenshot"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - macOS native TTS
// ═══════════════════════════════════════════════════════════════════

/// Native macOS text-to-speech using NSSpeechSynthesizer / AVSpeechSynthesizer.
public actor NativeTTS: MediaCapability {
    public nonisolated let capabilityID = "audio.tts"
    public nonisolated let displayName = "Native TTS"
    public var isAvailable: Bool { true }

    public init() {}

    public func execute(_ request: MediaRequest) async throws -> MediaResult {
        guard case .textToSpeech(let text, _) = request else {
            throw MediaError.invalidRequest("Expected textToSpeech request")
        }
        // Use macOS `say` command as a simple TTS backend
        let process = Process()
        let outputFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).aiff")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", outputFile.path, text]
        try process.run()
        process.waitUntilExit()
        let data = try Data(contentsOf: outputFile)
        try? FileManager.default.removeItem(at: outputFile)
        return .audio(data, mimeType: "audio/aiff")
    }
}

public enum MediaError: Error, Sendable {
    case capabilityNotAvailable(String)
    case invalidRequest(String)
    case processingFailed(String)
}
