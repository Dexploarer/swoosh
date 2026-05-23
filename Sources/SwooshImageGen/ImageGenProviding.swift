// SwooshImageGen/ImageGenProviding.swift
// Version: 0.9R
//
// Local-first text-to-image. Apple Image Playground (macOS 15.2+/iOS 18.2+)
// is the on-device path — free, private, no model download. Cloud fallback
// (OpenAI gpt-image-1) for higher fidelity or when Image Playground is
// not available on the OS.

import Foundation

public protocol ImageGenProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    var supportsCustomSize: Bool { get }
    func supportedStyles() async -> [ImageGenStyle]
    func generate(_ request: ImageGenRequest) async throws -> ImageGenResult
}

public struct ImageGenRequest: Sendable {
    public let prompt: String
    public let negativePrompt: String?
    public let style: ImageGenStyle?
    public let width: Int
    public let height: Int
    /// Random seed (0 = random). Not all providers honor this.
    public let seed: UInt64

    public init(
        prompt: String,
        negativePrompt: String? = nil,
        style: ImageGenStyle? = nil,
        width: Int = 1024,
        height: Int = 1024,
        seed: UInt64 = 0
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.style = style
        self.width = width
        self.height = height
        self.seed = seed
    }
}

public struct ImageGenStyle: Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) {
        self.id = id; self.displayName = displayName
    }
}

public struct ImageGenResult: Codable, Sendable {
    /// PNG-encoded image data.
    public let pngData: Data
    public let providerID: String
    public let usedStyle: String?
    public init(pngData: Data, providerID: String, usedStyle: String? = nil) {
        self.pngData = pngData
        self.providerID = providerID
        self.usedStyle = usedStyle
    }
}

public enum ImageGenError: Error, CustomStringConvertible, Sendable {
    case unsupportedPlatform
    case unsupportedOSVersion
    case generationFailed(String)
    case missingAPIKey(String)

    public var description: String {
        switch self {
        case .unsupportedPlatform:
            return "Image generation unavailable on this platform."
        case .unsupportedOSVersion:
            return "Image Playground requires macOS 15.2 / iOS 18.2 or newer."
        case .generationFailed(let m):
            return "Image generation failed: \(m)"
        case .missingAPIKey(let p):
            return "Missing API key for \(p)."
        }
    }
}
