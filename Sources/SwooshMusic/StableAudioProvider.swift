// SwooshMusic/StableAudioProvider.swift — 0.9R Stability AI Stable Audio
//
// Stability AI's Stable Audio 2 — open-weights model, also available
// via Stability's hosted API. Generates up to 3-minute clips from a
// text prompt; optional input audio for variation / extension.
//
// Endpoint: POST /v2beta/audio/stable-audio-2

import Foundation

public actor StableAudioProvider: MusicProviding {

    public nonisolated let displayName = "Stable Audio"
    public nonisolated let id = "stable-audio"
    public nonisolated let availableModels: [MusicModel] = [
        MusicModel(id: "stable-audio-2", displayName: "Stable Audio 2", maxDuration: 190),
    ]

    private let apiKeyProvider: @Sendable () async throws -> String
    private let session: URLSession

    public init(
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    public func generate(_ request: MusicRequest) async throws -> MusicJob {
        let apiKey: String
        do { apiKey = try await apiKeyProvider() }
        catch { throw MusicError.missingAPIKey(displayName) }

        guard let url = URL(string: "https://api.stability.ai/v2beta/audio/stable-audio-2/text-to-audio") else {
            throw MusicError.requestFailed("invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        // multipart/form-data
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        append("prompt", request.prompt)
        if let duration = request.durationSeconds {
            append("duration", String(Int(duration)))
        }
        if let style = request.style {
            append("style", style)
        }
        append("output_format", "mp3")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw MusicError.requestFailed("HTTP \(status): \(preview)")
        }
        // Direct binary response.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("stable-audio-\(UUID().uuidString).mp3")
        try data.write(to: tmp)
        return InlineMusicJob(
            id: tmp.lastPathComponent,
            url: tmp,
            modelUsed: "stable-audio-2",
            prompt: request.prompt
        )
    }
}
