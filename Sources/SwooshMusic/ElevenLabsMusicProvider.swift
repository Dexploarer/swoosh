// SwooshMusic/ElevenLabsMusicProvider.swift — 0.9R ElevenLabs Music
//
// ElevenLabs shipped music generation alongside their TTS. Their music
// API takes a text prompt and returns audio directly — no separate
// job polling needed for shorter clips.
//
// Endpoint: POST /v1/music

import Foundation

public actor ElevenLabsMusicProvider: MusicProviding {

    public nonisolated let displayName = "ElevenLabs Music"
    public nonisolated let id = "elevenlabs-music"
    public nonisolated let availableModels: [MusicModel] = [
        MusicModel(id: "music_v1", displayName: "ElevenLabs Music v1", maxDuration: 60),
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

        guard let url = URL(string: "https://api.elevenlabs.io/v1/music") else {
            throw MusicError.requestFailed("invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "prompt": request.prompt,
            "model_id": request.model ?? "music_v1",
        ]
        if let duration = request.durationSeconds {
            body["music_length_ms"] = Int(duration * 1000)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw MusicError.requestFailed("HTTP \(status): \(preview)")
        }
        // Direct response — write to a temp file and return its URL.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("elevenlabs-music-\(UUID().uuidString).mp3")
        try data.write(to: tmp)
        return InlineMusicJob(
            id: tmp.lastPathComponent,
            url: tmp,
            modelUsed: request.model ?? "music_v1",
            prompt: request.prompt
        )
    }
}
