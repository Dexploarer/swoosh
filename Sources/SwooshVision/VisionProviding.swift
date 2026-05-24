// SwooshVision/VisionProviding.swift
// Version: 0.9S
//
// Local-first vision capabilities backed by Apple's Vision framework.
// Every method returns plain Sendable values so the daemon can serialize
// results to the iPhone over HTTP without touching CGImage on the wire.
//
// Capabilities exposed today:
//   • OCR (VNRecognizeTextRequest)                              — shipping
//   • Foreground subject mask (VNGenerateForegroundInstanceMask) — macOS 14+/iOS 17+
//   • Document recognition                                       — **OCR-only fallback**;
//     `tables` is always empty until VNRecognizeDocumentsRequest
//     stabilises in a toolchain we can compile against.
//   • Face detection (VNDetectFaceRectanglesRequest)             — shipping
//   • Depth map                                                  — **always throws**
//     `unsupportedOSVersion("Depth estimation")` until a real
//     `VNGenerateDepthRequest` impl lands. `supportedCapabilities()`
//     deliberately omits `.depth`.
//
// Cross-platform: builds on macOS, iOS, and visionOS. No Process, no
// SQLite — safe for the iOS app to import directly.

import Foundation

#if canImport(Vision)
import Vision
#endif

// MARK: - Capability surface

public enum VisionCapability: String, Codable, Sendable, CaseIterable {
    case ocr
    case foregroundMask
    case depth
    case documentRecognition
    case faceDetection

    public var displayName: String {
        switch self {
        case .ocr:                  return "Text recognition"
        case .foregroundMask:       return "Subject lift"
        case .depth:                return "Depth estimation"
        case .documentRecognition:  return "Document layout"
        case .faceDetection:        return "Face detection"
        }
    }

    public var systemImage: String {
        switch self {
        case .ocr:                  return "text.viewfinder"
        case .foregroundMask:       return "person.crop.rectangle"
        case .depth:                return "square.3.layers.3d"
        case .documentRecognition:  return "doc.text.magnifyingglass"
        case .faceDetection:        return "face.smiling"
        }
    }
}

// MARK: - Errors

public enum VisionProviderError: Error, CustomStringConvertible, Sendable {
    case unsupportedPlatform
    case unsupportedOSVersion(String)
    case invalidImage
    case requestFailed(String)

    public var description: String {
        switch self {
        case .unsupportedPlatform:
            return "Vision is unavailable on this platform."
        case .unsupportedOSVersion(let cap):
            return "\(cap) requires a newer OS version."
        case .invalidImage:
            return "Could not decode image data."
        case .requestFailed(let m):
            return "Vision request failed: \(m)"
        }
    }
}

// MARK: - Sendable result types

public struct VisionTextBlock: Codable, Sendable {
    public let text: String
    public let confidence: Float
    /// Normalised bounding box (origin lower-left, range 0…1).
    public let normalizedBoundingBox: VisionRect

    public init(text: String, confidence: Float, normalizedBoundingBox: VisionRect) {
        self.text = text
        self.confidence = confidence
        self.normalizedBoundingBox = normalizedBoundingBox
    }
}

public struct VisionFace: Codable, Sendable {
    public let normalizedBoundingBox: VisionRect
    public let roll: Double?
    public let yaw: Double?
    public let pitch: Double?

    public init(normalizedBoundingBox: VisionRect, roll: Double? = nil, yaw: Double? = nil, pitch: Double? = nil) {
        self.normalizedBoundingBox = normalizedBoundingBox
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
    }
}

public struct VisionRect: Codable, Sendable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct VisionMaskResult: Codable, Sendable {
    /// PNG-encoded grayscale mask. Empty when no subject is detected.
    public let pngData: Data
    public let subjectCount: Int

    public init(pngData: Data, subjectCount: Int) {
        self.pngData = pngData
        self.subjectCount = subjectCount
    }
}

public struct VisionDepthResult: Codable, Sendable {
    /// 16-bit-per-channel PNG depth map (relative depth, near = darker).
    public let pngData: Data
    public let width: Int
    public let height: Int

    public init(pngData: Data, width: Int, height: Int) {
        self.pngData = pngData; self.width = width; self.height = height
    }
}

public struct VisionDocumentResult: Codable, Sendable {
    public let plainText: String
    public let paragraphs: [String]
    public let tables: [VisionTable]

    public init(plainText: String, paragraphs: [String], tables: [VisionTable]) {
        self.plainText = plainText
        self.paragraphs = paragraphs
        self.tables = tables
    }
}

public struct VisionTable: Codable, Sendable {
    public let rows: [[String]]
    public init(rows: [[String]]) { self.rows = rows }
}

// MARK: - Provider protocol

public protocol VisionProviding: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isLocal: Bool { get }
    func supportedCapabilities() -> Set<VisionCapability>
    func recognizeText(in imageData: Data, languages: [String]) async throws -> [VisionTextBlock]
    func subjectMask(in imageData: Data) async throws -> VisionMaskResult
    func depthMap(from imageData: Data) async throws -> VisionDepthResult
    func recognizeDocument(in imageData: Data, languages: [String]) async throws -> VisionDocumentResult
    func detectFaces(in imageData: Data) async throws -> [VisionFace]
}

// MARK: - Default extensions (helpers for callers)

extension VisionProviding {
    public func recognizeText(in imageData: Data) async throws -> [VisionTextBlock] {
        try await recognizeText(in: imageData, languages: ["en-US"])
    }

    public func recognizeDocument(in imageData: Data) async throws -> VisionDocumentResult {
        try await recognizeDocument(in: imageData, languages: ["en-US"])
    }
}
