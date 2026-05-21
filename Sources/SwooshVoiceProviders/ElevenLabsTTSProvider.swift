// SwooshVoiceProviders/ElevenLabsTTSProvider.swift — 0.9R ElevenLabs TTS
//
// Wraps `POST /v1/text-to-speech/{voice_id}` from the ElevenLabs API.
// Voice cloning + emotion control + 30+ languages. API key required.
//
// Endpoint reference: https://elevenlabs.io/docs/api-reference/text-to-speech

import Foundation

public actor ElevenLabsTTSProvider: TTSProviding {

    public nonisolated let displayName = "ElevenLabs"
    public nonisolated let id = "elevenlabs"
    public nonisolated let isCloud = true
    public nonisolated let signupURL: URL? = URL(string: "https://elevenlabs.io/app/settings/api-keys")

    /// Default voice id ("Rachel" — `21m00Tcm4TlvDq8ikWAM`). Override
    /// per-call via the `voiceID` argument.
    public let defaultVoiceID: String

    /// Optional model id — `eleven_turbo_v2_5` is the fastest current.
    public let modelID: String

    /// Secret resolver — supplies the API key from Keychain.
    private let apiKeyProvider: @Sendable () async throws -> String

    private let session: URLSession

    public init(
        defaultVoiceID: String = "21m00Tcm4TlvDq8ikWAM",
        modelID: String = "eleven_turbo_v2_5",
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.defaultVoiceID = defaultVoiceID
        self.modelID = modelID
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    public func synthesize(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) async throws -> TTSResult {
        let apiKey: String
        do {
            apiKey = try await apiKeyProvider()
        } catch {
            throw TTSError.missingAPIKey(displayName)
        }
        let voice = voiceID ?? defaultVoiceID
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)") else {
            throw TTSError.requestFailed("invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(format.elevenLabsAccept, forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TTSError.requestFailed("HTTP \(status): \(preview)")
        }
        return TTSResult(audioData: data, mimeType: format.mimeType, voiceUsed: voice)
    }

    /// Streaming — uses ElevenLabs' `/v1/text-to-speech/{id}/stream`
    /// endpoint which returns chunked MP3 as the model decodes.
    public nonisolated func synthesizeStream(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await apiKeyProvider()
                    let voice = voiceID ?? defaultVoiceID
                    guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream") else {
                        throw TTSError.requestFailed("invalid URL")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
                    request.setValue(format.elevenLabsAccept, forHTTPHeaderField: "Accept")
                    let body: [String: Any] = [
                        "text": text,
                        "model_id": modelID,
                        "voice_settings": ["stability": 0.5, "similarity_boost": 0.75],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw TTSError.requestFailed("HTTP \(http.statusCode)")
                    }
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 4096 {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Fetch available voices (cached or live). Useful for picker UI.
    public func voices() async throws -> [TTSVoice] {
        let apiKey = try await apiKeyProvider()
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, _) = try await session.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voices = json["voices"] as? [[String: Any]] else { return [] }

        return voices.compactMap { v in
            guard let id = v["voice_id"] as? String,
                  let name = v["name"] as? String else { return nil }
            let preview = (v["preview_url"] as? String).flatMap(URL.init(string:))
            return TTSVoice(id: id, displayName: name, preview: preview)
        }
    }
}

private extension TTSAudioFormat {
    var elevenLabsAccept: String {
        switch self {
        case .mp3:  return "audio/mpeg"
        case .wav:  return "audio/wav"
        case .opus: return "audio/ogg"
        case .aac:  return "audio/aac"
        case .pcm:  return "audio/wav"  // ElevenLabs has no raw PCM — fall to WAV.
        }
    }
}
