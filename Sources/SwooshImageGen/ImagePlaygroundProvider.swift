// SwooshImageGen/ImagePlaygroundProvider.swift
// Version: 0.9S
//
// Apple Image Playground (macOS 15.2+/iOS 18.2+). Gated on Apple
// Intelligence availability at runtime. When unavailable the router
// falls through to the cloud fallback.
//
// Optional `firewall` + `auditLog` enforce `.imageGenerate` permission
// and emit `AuditEntry` records around every generation request. The
// iOS picker path passes nil; daemon-side tool wrappers pass real impls.
// The registry-mounted `GenerateImageTool` is the primary gate; these
// injections are defense-in-depth for direct (non-registry) callers.

import Foundation
import SwooshTools

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

    private let gate: MediaAuditGate

    public init(
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.gate = MediaAuditGate(
            toolName: "apple-image-playground",
            permission: .imageGenerate,
            firewall: firewall,
            auditLog: auditLog
        )
    }

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
        try await gate.requirePermission()
        let promptHash = MediaAuditGate.promptDigest(request.prompt)
        await gate.started("local promptHash=\(promptHash) style=\(request.style?.id ?? "default")")
        #if canImport(ImagePlayground)
        guard #available(macOS 15.2, iOS 18.2, *) else {
            await gate.failed("OS unsupported")
            throw ImageGenError.unsupportedOSVersion
        }
        return try await renderWithImagePlayground(request: request)
        #else
        await gate.failed("platform unsupported")
        throw ImageGenError.unsupportedPlatform
        #endif
    }

    #if canImport(ImagePlayground)
    @available(macOS 15.2, iOS 18.2, *)
    private func renderWithImagePlayground(request: ImageGenRequest) async throws -> ImageGenResult {
        let creator: ImageCreator
        do {
            creator = try await ImageCreator()
        } catch {
            await gate.failed("ImageCreator init failed")
            throw ImageGenError.generationFailed("ImageCreator init failed: \(error.localizedDescription)")
        }
        let style = mapStyle(request.style)
        let concepts: [ImagePlaygroundConcept] = [.text(request.prompt)]
        do {
            let images = creator.images(for: concepts, style: style, limit: 1)
            for try await image in images {
                if let png = pngData(from: image.cgImage) {
                    await gate.succeeded("bytes=\(png.count)")
                    return ImageGenResult(pngData: png, providerID: id, usedStyle: request.style?.id)
                }
            }
        } catch {
            await gate.failed("generation failed")
            throw ImageGenError.generationFailed(error.localizedDescription)
        }
        await gate.failed("no images returned")
        throw ImageGenError.generationFailed("Image Playground returned no images")
    }
    #endif

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
