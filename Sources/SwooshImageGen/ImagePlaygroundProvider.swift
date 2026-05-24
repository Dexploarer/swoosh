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

    private let firewall: (any Firewall)?
    private let auditLog: (any AuditLogging)?

    public init(
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.firewall = firewall
        self.auditLog = auditLog
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

    private func audit(_ kind: AuditEntryKind, _ detail: String, success: Bool = true) async {
        guard let auditLog else { return }
        try? await auditLog.append(AuditEntry(
            kind: kind, toolName: id, detail: detail, success: success
        ))
    }

    private func requirePermission() async throws {
        guard let firewall else { return }
        do {
            try await firewall.require(.imageGenerate)
        } catch {
            await audit(.toolCallDenied, "denied", success: false)
            throw error
        }
    }

    public func generate(_ request: ImageGenRequest) async throws -> ImageGenResult {
        try await requirePermission()
        let promptHash = String(request.prompt.hash, radix: 16)
        await audit(.toolCallStarted, "local promptHash=\(promptHash) style=\(request.style?.id ?? "default")")
        #if canImport(ImagePlayground)
        guard #available(macOS 15.2, iOS 18.2, *) else {
            await audit(.toolCallFailed, "OS unsupported", success: false)
            throw ImageGenError.unsupportedOSVersion
        }
        let creator: ImageCreator
        do {
            creator = try await ImageCreator()
        } catch {
            await audit(.toolCallFailed, "ImageCreator init failed", success: false)
            throw ImageGenError.generationFailed("ImageCreator init failed: \(error.localizedDescription)")
        }
        let style = mapStyle(request.style)
        let concepts: [ImagePlaygroundConcept] = [.text(request.prompt)]
        do {
            let images = creator.images(for: concepts, style: style, limit: 1)
            for try await image in images {
                if let png = pngData(from: image.cgImage) {
                    await audit(.toolCallSucceeded, "bytes=\(png.count)")
                    return ImageGenResult(pngData: png, providerID: id, usedStyle: request.style?.id)
                }
            }
        } catch {
            await audit(.toolCallFailed, "generation failed", success: false)
            throw ImageGenError.generationFailed(error.localizedDescription)
        }
        await audit(.toolCallFailed, "no images returned", success: false)
        throw ImageGenError.generationFailed("Image Playground returned no images")
        #else
        await audit(.toolCallFailed, "platform unsupported", success: false)
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
