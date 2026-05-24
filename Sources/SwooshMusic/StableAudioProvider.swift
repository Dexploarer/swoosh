// SwooshMusic/StableAudioProvider.swift — 0.9S Stability AI Stable Audio
//
// Stability AI's Stable Audio 2 — open-weights model, also available
// via Stability's hosted API. Generates up to 3-minute clips from a
// text prompt; optional input audio for variation / extension.
//
// Endpoint: POST /v2beta/audio/stable-audio-2
//
// Optional `firewall` + `auditLog` enforce `.musicGenerate` permission
// and emit `AuditEntry` records around every generation request. The
// iOS picker path passes nil; daemon-side tool wrappers pass real impls.
// The registry-mounted `GenerateMusicTool` is the primary gate; these
// injections are defense-in-depth for direct (non-registry) callers.

import Foundation
import SwooshTools

public actor StableAudioProvider: MusicProviding {

    public nonisolated let displayName = "Stable Audio"
    public nonisolated let id = "stable-audio"
    public nonisolated let availableModels: [MusicModel] = [
        MusicModel(id: "stable-audio-2", displayName: "Stable Audio 2", maxDuration: 190),
    ]

    private let apiKeyProvider: @Sendable () async throws -> String
    private let session: URLSession
    private let gate: MediaAuditGate

    public init(
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared,
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.gate = MediaAuditGate(
            toolName: "stable-audio",
            permission: .musicGenerate,
            firewall: firewall,
            auditLog: auditLog
        )
    }

    public func generate(_ request: MusicRequest) async throws -> MusicJob {
        try await gate.requirePermission()
        let promptHash = MediaAuditGate.promptDigest(request.prompt)
        await gate.started("promptHash=\(promptHash)")

        let apiKey: String
        do { apiKey = try await apiKeyProvider() }
        catch {
            await gate.failed("missing API key")
            throw MusicError.missingAPIKey(displayName)
        }

        let data = try await postAndGet(request: request, apiKey: apiKey)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stable-audio-\(UUID().uuidString).mp3")
        try data.write(to: tmp)
        await gate.succeeded("bytes=\(data.count)")
        return InlineMusicJob(
            id: tmp.lastPathComponent,
            url: tmp,
            modelUsed: "stable-audio-2",
            prompt: request.prompt
        )
    }

    private func postAndGet(request: MusicRequest, apiKey: String) async throws -> Data {
        guard let url = URL(string: "https://api.stability.ai/v2beta/audio/stable-audio-2/text-to-audio") else {
            await gate.failed("invalid URL")
            throw MusicError.requestFailed("invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.encodeMultipart(request: request, boundary: boundary)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            await gate.failed("HTTP \(status)")
            throw MusicError.requestFailed("HTTP \(status): \(preview)")
        }
        return data
    }

    private static func encodeMultipart(request: MusicRequest, boundary: String) -> Data {
        var body = Data()
        func append(_ name: String, _ value: String) {
            let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            body.append(Data(header.utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        append("prompt", request.prompt)
        if let duration = request.durationSeconds {
            append("duration", String(Int(duration)))
        }
        if let style = request.style {
            append("style", style)
        }
        append("output_format", "mp3")
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
