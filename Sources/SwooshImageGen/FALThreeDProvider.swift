// SwooshImageGen/FALThreeDProvider.swift
// Version: 0.9R
//
// FAL.ai text/image-to-3D. Routes through the shared FALClient queue.
//
// Optional `firewall` + `auditLog` enforce `.threeDGenerate` permission
// and emit `AuditEntry` records around every generation request.

import Foundation
import SwooshTools

public actor FALThreeDProvider: ThreeDGenProviding {

    public static let supportedFALModels: [ThreeDGenModel] = [
        ThreeDGenModel(
            id: "fal-ai/tripo3d",
            displayName: "Tripo3D v2.5",
            supportsTextInput: true,
            supportsImageInput: true,
            outputFormats: [.glb, .usdz]
        ),
        ThreeDGenModel(
            id: "fal-ai/trellis",
            displayName: "Trellis (Microsoft)",
            supportsTextInput: false,
            supportsImageInput: true,
            outputFormats: [.glb, .ply]
        ),
        ThreeDGenModel(
            id: "fal-ai/triposr",
            displayName: "TripoSR",
            supportsTextInput: false,
            supportsImageInput: true,
            outputFormats: [.glb, .obj]
        ),
        ThreeDGenModel(
            id: "fal-ai/hunyuan3d/v2",
            displayName: "Hunyuan3D 2.0",
            supportsTextInput: true,
            supportsImageInput: true,
            outputFormats: [.glb]
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

    public nonisolated var id: String { "fal-3d" }
    public nonisolated var displayName: String { "FAL.ai 3D (cloud)" }
    public nonisolated var isLocal: Bool { false }

    public func supportedModels() async -> [ThreeDGenModel] {
        Self.supportedFALModels
    }

    public func generate(_ request: ThreeDGenRequest) async throws -> ThreeDGenResult {
        if let firewall {
            do {
                try await firewall.require(.threeDGenerate)
            } catch {
                await audit(.toolCallDenied, "denied: \(request.modelID)", success: false)
                throw error
            }
        }
        guard let model = Self.supportedFALModels.first(where: { $0.id == request.modelID }) else {
            await audit(.toolCallFailed, "unsupported model: \(request.modelID)", success: false)
            throw ThreeDGenError.unsupportedModel(request.modelID)
        }
        guard model.outputFormats.contains(request.outputFormat) else {
            await audit(.toolCallFailed, "unsupported format \(request.outputFormat.rawValue) for \(request.modelID)", success: false)
            throw ThreeDGenError.unsupportedOutputFormat(request.outputFormat)
        }
        let promptHash = String((request.prompt ?? "").hash, radix: 16)
        await audit(
            .toolCallStarted,
            "model=\(request.modelID) format=\(request.outputFormat.rawValue) promptHash=\(promptHash) hasImage=\(request.imagePNG != nil)"
        )

        var payload: [String: Any] = [
            "output_format": request.outputFormat.rawValue
        ]
        if let prompt = request.prompt, model.supportsTextInput {
            payload["prompt"] = prompt
        }
        if let png = request.imagePNG, model.supportsImageInput {
            payload["image_url"] = "data:image/png;base64,\(png.base64EncodedString())"
        }
        if request.seed > 0 {
            payload["seed"] = request.seed
        }

        let payloadData: Data
        do {
            payloadData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw ThreeDGenError.generationFailed("Encode failed: \(error)")
        }
        let responseData: Data
        do {
            responseData = try await client.runQueued(modelID: request.modelID, payload: payloadData)
        } catch FALClient.FALError.missingAPIKey {
            await audit(.toolCallFailed, "missing FAL key", success: false)
            throw ThreeDGenError.missingAPIKey("fal")
        } catch FALClient.FALError.queueTimeout {
            await audit(.toolCallFailed, "queue timeout: \(request.modelID)", success: false)
            throw ThreeDGenError.queueTimeout
        } catch {
            await audit(.toolCallFailed, "failed: \(String(describing: error).prefix(80))", success: false)
            throw ThreeDGenError.generationFailed(String(describing: error))
        }
        let response = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] ?? [:]

        // Common shapes across FAL 3D models. Try each in order.
        let candidateKeys = ["model_mesh", "glb", "mesh", "output_file"]
        var assetURL: String?
        for key in candidateKeys {
            if let dict = response[key] as? [String: Any], let url = dict["url"] as? String {
                assetURL = url; break
            }
            if let url = response[key] as? String {
                assetURL = url; break
            }
        }
        guard let url = assetURL else {
            throw ThreeDGenError.generationFailed("FAL response missing 3D asset URL")
        }
        let data: Data
        do {
            data = try await client.download(url)
        } catch {
            throw ThreeDGenError.generationFailed("Download failed: \(error)")
        }
        await audit(.toolCallSucceeded, "model=\(request.modelID) bytes=\(data.count)")
        return ThreeDGenResult(
            modelData: data,
            format: request.outputFormat,
            providerID: id,
            modelID: request.modelID
        )
    }
}
