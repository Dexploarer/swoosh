// SwooshVoiceProviders/CartesiaTTSProvider.swift — 0.9R Cartesia Sonic TTS
//
// Cartesia's Sonic model — currently the fastest commercial TTS (40ms
// first-byte latency). Built for real-time voice agents.
//
// Endpoint: POST /tts/bytes
// Reference: https://docs.cartesia.ai/api-reference/tts/bytes

import Foundation

public actor CartesiaTTSProvider: TTSProviding {

    public nonisolated let displayName = "Cartesia Sonic"
    public nonisolated let id = "cartesia"
    public nonisolated let isCloud = true
    public nonisolated let signupURL: URL? = URL(string: "https://play.cartesia.ai/keys")

    public let defaultVoiceID: String
    public let model: String

    private let apiKeyProvider: @Sendable () async throws -> String
    private let session: URLSession

    public init(
        defaultVoiceID: String = "a0e99841-438c-4a64-b679-ae501e7d6091", // "Barbershop Man" — Cartesia's demo
        model: String = "sonic-english",
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.defaultVoiceID = defaultVoiceID
        self.model = model
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

        guard let url = URL(string: "https://api.cartesia.ai/tts/bytes") else {
            throw TTSError.requestFailed("invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("2024-06-10", forHTTPHeaderField: "Cartesia-Version")

        let voice = voiceID ?? defaultVoiceID
        let body: [String: Any] = [
            "model_id": model,
            "transcript": text,
            "voice": [
                "mode": "id",
                "id": voice,
            ],
            "output_format": [
                "container": format.cartesiaContainer,
                "encoding": format.cartesiaEncoding,
                "sample_rate": 44_100,
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

    /// Streaming — Cartesia's `/tts/sse` endpoint frames audio chunks
    /// as Server-Sent Events. Each event has a `data:` line with
    /// JSON containing a base64 audio payload that we decode and yield.
    public nonisolated func synthesizeStream(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await apiKeyProvider()
                    guard let url = URL(string: "https://api.cartesia.ai/tts/sse") else {
                        throw TTSError.requestFailed("invalid URL")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                    request.setValue("2024-06-10", forHTTPHeaderField: "Cartesia-Version")

                    let voice = voiceID ?? defaultVoiceID
                    let body: [String: Any] = [
                        "model_id": model,
                        "transcript": text,
                        "voice": ["mode": "id", "id": voice],
                        "output_format": [
                            "container": format.cartesiaContainer,
                            "encoding": format.cartesiaEncoding,
                            "sample_rate": 44_100,
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw TTSError.requestFailed("HTTP \(http.statusCode)")
                    }

                    var lineBuffer = ""
                    for try await byte in bytes {
                        let scalar = UnicodeScalar(byte)
                        let ch = Character(scalar)
                        if ch == "\n" {
                            if lineBuffer.hasPrefix("data: ") {
                                let payload = String(lineBuffer.dropFirst(6))
                                if let payloadData = payload.data(using: .utf8),
                                   let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                                   let audioBase64 = obj["data"] as? String,
                                   let chunk = Data(base64Encoded: audioBase64) {
                                    continuation.yield(chunk)
                                }
                            }
                            lineBuffer = ""
                        } else {
                            lineBuffer.append(ch)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Fetch the user's available voices via `GET /voices`.
    public func voices() async throws -> [TTSVoice] {
        let apiKey = try await apiKeyProvider()
        guard let url = URL(string: "https://api.cartesia.ai/voices") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("2024-06-10", forHTTPHeaderField: "Cartesia-Version")

        let (data, _) = try await session.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { v in
            guard let id = v["id"] as? String,
                  let name = v["name"] as? String else { return nil }
            let lang = (v["language"] as? String)
            return TTSVoice(id: id, displayName: name, language: lang)
        }
    }
}

private extension TTSAudioFormat {
    var cartesiaContainer: String {
        switch self {
        case .mp3:  return "mp3"
        case .wav:  return "wav"
        case .opus: return "opus"
        case .aac:  return "aac"
        case .pcm:  return "raw"
        }
    }
    var cartesiaEncoding: String {
        switch self {
        case .mp3, .opus: return "mp3"
        case .wav, .pcm:  return "pcm_s16le"
        case .aac:        return "aac"
        }
    }
}
