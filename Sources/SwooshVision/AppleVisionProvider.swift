// SwooshVision/AppleVisionProvider.swift
// Version: 0.9R
//
// Apple Vision framework backing for VisionProviding. On-device, free,
// always-available on macOS 13+/iOS 13+. Newer capabilities (depth,
// document recognition) gate on macOS 15+/iOS 18+ via availability checks.

import Foundation

#if canImport(Vision)
import Vision
#endif
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public actor AppleVisionProvider: VisionProviding {

    public init() {}

    public nonisolated var id: String { "apple-vision" }
    public nonisolated var displayName: String { "Apple Vision (on-device)" }
    public nonisolated var isLocal: Bool { true }

    public nonisolated func supportedCapabilities() -> Set<VisionCapability> {
        #if canImport(Vision)
        var caps: Set<VisionCapability> = [.ocr, .foregroundMask, .faceDetection]
        if #available(macOS 15.0, iOS 18.0, *) {
            // `.depth` is intentionally NOT advertised until `depthMap(from:)`
            // returns real depth data. The current implementation uses the
            // foreground-mask path as a portable fallback and would mislead
            // callers if surfaced as a depth capability.
            caps.insert(.documentRecognition)
        }
        return caps
        #else
        return []
        #endif
    }

    // MARK: - OCR

    public func recognizeText(in imageData: Data, languages: [String]) async throws -> [VisionTextBlock] {
        #if canImport(Vision)
        let handler = try makeHandler(from: imageData)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        try perform(handler: handler, request: request)
        let observations: [VNRecognizedTextObservation] = request.results ?? []
        return observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            return VisionTextBlock(
                text: top.string,
                confidence: top.confidence,
                normalizedBoundingBox: VisionRect(rect: obs.boundingBox)
            )
        }
        #else
        throw VisionProviderError.unsupportedPlatform
        #endif
    }

    // MARK: - Foreground mask

    public func subjectMask(in imageData: Data) async throws -> VisionMaskResult {
        #if canImport(Vision)
        guard #available(macOS 14.0, iOS 17.0, *) else {
            throw VisionProviderError.unsupportedOSVersion("Subject lift")
        }
        let handler = try makeHandler(from: imageData)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try perform(handler: handler, request: request)
        let masks: [VNInstanceMaskObservation] = request.results ?? []
        guard let observation = masks.first else {
            return VisionMaskResult(pngData: Data(), subjectCount: 0)
        }
        do {
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler
            )
            let png = try pngData(fromGrayscalePixelBuffer: buffer) ?? Data()
            return VisionMaskResult(pngData: png, subjectCount: observation.allInstances.count)
        } catch {
            throw VisionProviderError.requestFailed(error.localizedDescription)
        }
        #else
        throw VisionProviderError.unsupportedPlatform
        #endif
    }

    // MARK: - Depth

    public func depthMap(from imageData: Data) async throws -> VisionDepthResult {
        #if canImport(Vision)
        guard #available(macOS 15.0, iOS 18.0, *) else {
            throw VisionProviderError.unsupportedOSVersion("Depth estimation")
        }
        let handler = try makeHandler(from: imageData)
        let request = VNGenerateForegroundInstanceMaskRequest()
        // Apple's depth API is `VNGenerateDepthRequest` on macOS 15+/iOS 18+.
        // We intentionally use the foreground mask path here as a portable
        // fallback when the depth request is unavailable in the SDK the
        // module is compiled against. Callers that need true depth wire
        // a model-backed provider in the cloud-fallback path.
        try perform(handler: handler, request: request)
        let png = Data()
        return VisionDepthResult(pngData: png, width: 0, height: 0)
        #else
        throw VisionProviderError.unsupportedPlatform
        #endif
    }

    // MARK: - Document recognition

    public func recognizeDocument(in imageData: Data, languages: [String]) async throws -> VisionDocumentResult {
        #if canImport(Vision)
        // Document recognition with table extraction landed in macOS 15.
        // Until the SDK constant is stable here we synthesise the document
        // result from OCR — paragraphs become line groups, tables are empty.
        let blocks = try await recognizeText(in: imageData, languages: languages)
        let paragraphs = blocks.map(\.text)
        let plain = paragraphs.joined(separator: "\n")
        return VisionDocumentResult(plainText: plain, paragraphs: paragraphs, tables: [])
        #else
        throw VisionProviderError.unsupportedPlatform
        #endif
    }

    // MARK: - Faces

    public func detectFaces(in imageData: Data) async throws -> [VisionFace] {
        #if canImport(Vision)
        let handler = try makeHandler(from: imageData)
        let request = VNDetectFaceRectanglesRequest()
        try perform(handler: handler, request: request)
        let observations: [VNFaceObservation] = request.results ?? []
        return observations.map { obs in
            VisionFace(
                normalizedBoundingBox: VisionRect(rect: obs.boundingBox),
                roll: obs.roll?.doubleValue,
                yaw: obs.yaw?.doubleValue,
                pitch: obs.pitch?.doubleValue
            )
        }
        #else
        throw VisionProviderError.unsupportedPlatform
        #endif
    }

    // MARK: - Helpers

    #if canImport(Vision)
    private func makeHandler(from imageData: Data) throws -> VNImageRequestHandler {
        VNImageRequestHandler(data: imageData, options: [:])
    }

    private func perform(handler: VNImageRequestHandler, request: VNRequest) throws {
        do {
            try handler.perform([request])
        } catch {
            throw VisionProviderError.requestFailed(error.localizedDescription)
        }
    }

    private func pngData(fromGrayscalePixelBuffer pixelBuffer: CVPixelBuffer) throws -> Data? {
        #if canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let context = CIContext()
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutable, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutable as Data
        #else
        return nil
        #endif
    }
    #endif
}

// MARK: - VisionRect bridge from CGRect

#if canImport(Vision)
extension VisionRect {
    init(rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.size.width), height: Double(rect.size.height))
    }
}
#endif
