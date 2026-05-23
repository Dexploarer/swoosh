// SwooshImageGen/ImagePlaygroundProvider.swift
// Version: 0.9R
//
// Apple Image Playground (macOS 15.2+/iOS 18.2+). Gated on Apple
// Intelligence availability at runtime. When unavailable the router
// falls through to the cloud fallback.

import Foundation

#if canImport(ImagePlayground)
import ImagePlayground
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public actor ImagePlaygroundProvider: ImageGenProviding {

    public init() {}

    public nonisolated var id: String { "apple-image-playground" }
    public nonisolated var displayName: String { "Apple Image Playground (on-device)" }
    public nonisolated var isLocal: Bool { true }
    public nonisolated var supportsCustomSize: Bool { false }

    public func supportedStyles() async -> [ImageGenStyle] {
        [
            ImageGenStyle(id: "animation",    displayName: "Animation"),
            ImageGenStyle(id: "illustration", displayName: "Illustration"),
            ImageGenStyle(id: "sketch",       displayName: "Sketch"),
        ]
    }

    public func generate(_ request: ImageGenRequest) async throws -> ImageGenResult {
        #if canImport(ImagePlayground)
        guard #available(macOS 15.2, iOS 18.2, *) else {
            throw ImageGenError.unsupportedOSVersion
        }
        let creator: ImageCreator
        do {
            creator = try await ImageCreator()
        } catch {
            throw ImageGenError.generationFailed("ImageCreator init failed: \(error.localizedDescription)")
        }
        let style = mapStyle(request.style)
        let concepts: [ImagePlaygroundConcept] = [.text(request.prompt)]
        do {
            let images = creator.images(for: concepts, style: style, limit: 1)
            for try await image in images {
                if let png = pngData(from: image.cgImage) {
                    return ImageGenResult(pngData: png, providerID: id, usedStyle: request.style?.id)
                }
            }
        } catch {
            throw ImageGenError.generationFailed(error.localizedDescription)
        }
        throw ImageGenError.generationFailed("Image Playground returned no images")
        #else
        throw ImageGenError.unsupportedPlatform
        #endif
    }

    #if canImport(ImagePlayground)
    @available(macOS 15.2, iOS 18.2, *)
    private func mapStyle(_ style: ImageGenStyle?) -> ImagePlaygroundStyle {
        switch style?.id {
        case "animation":    return .animation
        case "illustration": return .illustration
        case "sketch":       return .sketch
        default:             return .animation
        }
    }
    #endif

    private func pngData(from cgImage: CGImage) -> Data? {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutable, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutable as Data
        #else
        return nil
        #endif
    }
}
