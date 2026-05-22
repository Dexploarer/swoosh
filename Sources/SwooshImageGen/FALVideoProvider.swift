// SwooshImageGen/FALVideoProvider.swift
// Version: 0.9R
//
// FAL.ai text/image-to-video. Wraps several FAL models behind one
// VideoGenProviding surface — the picker UI selects the modelID, the
// provider routes through the shared FALClient queue.
//
// Optional `firewall` + `auditLog` enforce `.videoGenerate` permission
// and emit `AuditEntry` records around every generation request. The
// iOS picker path passes nil; daemon-side tool wrappers pass real impls.

import Foundation
import SwooshTools

public actor FALVideoProvider: VideoGenProviding {

    public static let supportedFALModels: [VideoGenModel] = [
        VideoGenModel(
            id: "fal-ai/veo3",
            displayName: "Google Veo 3",
            supportsImageInput: true,
            maxDurationSeconds: 8
        ),
        VideoGenModel(
            id: "fal-ai/kling-video/v2/master/text-to-video",
            displayName: "Kling 2.0 Master",
            supportsImageInput: false,
            maxDurationSeconds: 10
        ),
        VideoGenModel(
            id: "fal-ai/kling-video/v2/master/image-to-video",
            displayName: "Kling 2.0 (image-to-video)",
            supportsImageInput: true,
            maxDurationSeconds: 10
        ),
        VideoGenModel(
            id: "fal-ai/hunyuan-video",
            displayName: "Hunyuan Video",
            supportsImageInput: false,
            maxDurationSeconds: 6
        ),
        VideoGenModel(
            id: "fal-ai/luma-dream-machine",
            displayName: "Luma Dream Machine",
            supportsImageInput: true,
            maxDurationSeconds: 5
        ),
    ]

    private let client: FALClient
    private let firewall: (any Firewall)?
    private let auditLog: (any AuditLogging)?

    public init(
        client: FALClient,
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.client = client
        self.firewall = firewall
        self.auditLog = auditLog
    }

    private func audit(_ kind: AuditEntryKind, _ detail: String, success: Bool = true) async {
        guard let auditLog else { return }
        try? await auditLog.append(AuditEntry(
            kind: kind, toolName: id, detail: detail, success: success
        ))
    }

    public nonisolated var id: String { "fal-video" }
    public nonisolated var displayName: String { "FAL.ai Video (cloud)" }
    public nonisolated var isLocal: Bool { false }

    public func supportedModels() async -> [VideoGenModel] {
        Self.supportedFALModels
    }

    public func generate(_ request: VideoGenRequest) async throws -> VideoGenResult {
        if let firewall {
            do {
                try await firewall.require(.videoGenerate)
            } catch {
                await audit(.toolCallDenied, "denied: \(request.modelID)", success: false)
                throw error
            }
        }
        guard Self.supportedFALModels.contains(where: { $0.id == request.modelID }) else {
            await audit(.toolCallFailed, "unsupported model: \(request.modelID)", success: false)
            throw VideoGenError.unsupportedModel(request.modelID)
        }
        // Audit prompt metadata only — never raw image bytes.
        let promptHash = String(request.prompt.hash, radix: 16)
        await audit(
            .toolCallStarted,
            "model=\(request.modelID) duration=\(request.durationSeconds)s promptHash=\(promptHash) hasImage=\(request.imagePNG != nil)"
        )

        var payload: [String: Any] = [
            "prompt": request.prompt,
            "duration": request.durationSeconds,
        ]
        if let negative = request.negativePrompt {
            payload["negative_prompt"] = negative
        }
        if request.seed > 0 {
            payload["seed"] = request.seed
        }
        if let png = request.imagePNG {
            payload["image_url"] = "data:image/png;base64,\(png.base64EncodedString())"
        }
        // Aspect-ratio hint for the picker's width/height pairing.
        payload["aspect_ratio"] = aspectRatio(width: request.width, height: request.height)

        let payloadData: Data
        do {
            payloadData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw VideoGenError.generationFailed("Encode failed: \(error)")
        }
        let responseData: Data
        do {
            responseData = try await client.runQueued(modelID: request.modelID, payload: payloadData)
        } catch FALClient.FALError.missingAPIKey {
            await audit(.toolCallFailed, "missing FAL key", success: false)
            throw VideoGenError.missingAPIKey("fal")
        } catch FALClient.FALError.queueTimeout {
            await audit(.toolCallFailed, "queue timeout: \(request.modelID)", success: false)
            throw VideoGenError.queueTimeout
        } catch {
            await audit(.toolCallFailed, "failed: \(String(describing: error).prefix(80))", success: false)
            throw VideoGenError.generationFailed(String(describing: error))
        }
        let response = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]
        guard let videoDict = response["video"] as? [String: Any],
              let url = videoDict["url"] as? String else {
            throw VideoGenError.generationFailed("FAL response missing video.url")
        }
        let mime = (videoDict["content_type"] as? String) ?? "video/mp4"
        let data: Data
        do {
            data = try await client.download(url)
        } catch {
            throw VideoGenError.generationFailed("Download failed: \(error)")
        }
        await audit(.toolCallSucceeded, "model=\(request.modelID) bytes=\(data.count)")
        return VideoGenResult(videoData: data, mimeType: mime, providerID: id, modelID: request.modelID)
    }

    private func aspectRatio(width: Int, height: Int) -> String {
        switch (width, height) {
        case (1280, 720), (1920, 1080): return "16:9"
        case (720, 1280), (1080, 1920): return "9:16"
        case (1024, 1024):              return "1:1"
        default:                        return "16:9"
        }
    }
}
