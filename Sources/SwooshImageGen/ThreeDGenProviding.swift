// SwooshImageGen/ThreeDGenProviding.swift
// Version: 0.9R
//
// Text/image-to-3D provider protocol. Cloud-only today. Returns a 3D
// asset (GLB by default; some providers also produce USDZ for Quick Look).

import Foundation

public protocol ThreeDGenProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    func supportedModels() async -> [ThreeDGenModel]
    func generate(_ request: ThreeDGenRequest) async throws -> ThreeDGenResult
}

public struct ThreeDGenRequest: Sendable {
    public let prompt: String?
    /// Optional seed image for image-to-3D (PNG bytes).
    public let imagePNG: Data?
    /// Provider-specific model identifier (e.g. `fal-ai/tripo3d`).
    public let modelID: String
    public let outputFormat: ThreeDOutputFormat
    public let seed: UInt64

    public init(
        prompt: String? = nil,
        imagePNG: Data? = nil,
        modelID: String,
        outputFormat: ThreeDOutputFormat = .glb,
        seed: UInt64 = 0
    ) {
        self.prompt = prompt
        self.imagePNG = imagePNG
        self.modelID = modelID
        self.outputFormat = outputFormat
        self.seed = seed
    }
}

public enum ThreeDOutputFormat: String, Codable, Sendable {
    case glb
    case usdz
    case obj
    case ply

    public var mimeType: String {
        switch self {
        case .glb:  return "model/gltf-binary"
        case .usdz: return "model/vnd.usdz+zip"
        case .obj:  return "model/obj"
        case .ply:  return "application/octet-stream"
        }
    }
}

public struct ThreeDGenModel: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let supportsTextInput: Bool
    public let supportsImageInput: Bool
    public let outputFormats: [ThreeDOutputFormat]

    public init(
        id: String, displayName: String,
        supportsTextInput: Bool, supportsImageInput: Bool,
        outputFormats: [ThreeDOutputFormat]
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsTextInput = supportsTextInput
        self.supportsImageInput = supportsImageInput
        self.outputFormats = outputFormats
    }
}

public struct ThreeDGenResult: Sendable {
    public let modelData: Data
    public let format: ThreeDOutputFormat
    public let providerID: String
    public let modelID: String

    public init(modelData: Data, format: ThreeDOutputFormat, providerID: String, modelID: String) {
        self.modelData = modelData
        self.format = format
        self.providerID = providerID
        self.modelID = modelID
    }
}

public enum ThreeDGenError: Error, CustomStringConvertible, Sendable {
    case missingAPIKey(String)
    case unsupportedModel(String)
    case unsupportedOutputFormat(ThreeDOutputFormat)
    case generationFailed(String)
    case queueTimeout

    public var description: String {
        switch self {
        case .missingAPIKey(let p):           return "Missing API key for \(p)."
        case .unsupportedModel(let m):        return "Model \(m) is not supported by this provider."
        case .unsupportedOutputFormat(let f): return "Output format \(f.rawValue) is not supported by this model."
        case .generationFailed(let m):        return "3D generation failed: \(m)"
        case .queueTimeout:                   return "3D generation timed out in the cloud queue."
        }
    }
}
