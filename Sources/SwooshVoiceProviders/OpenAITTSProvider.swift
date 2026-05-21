// SwooshVoiceProviders/OpenAITTSProvider.swift — 0.9R OpenAI TTS
//
// Wraps `POST /v1/audio/speech`. Cheap, fast, six built-in voices
// (alloy, echo, fable, onyx, nova, shimmer). Uses the user's standard
// OpenAI API key.
//
// Endpoint reference: https://platform.openai.com/docs/api-reference/audio/createSpeech

import Foundation

public actor OpenAITTSProvider: TTSProviding {

    public nonisolated let displayName = "OpenAI TTS"
    public nonisolated let id = "openai-tts"
    public nonisolated let isCloud = true
    public nonisolated let signupURL: URL? = URL(string: "https://platform.openai.com/api-keys")

    public let defaultVoice: String   // "alloy" / "echo" / "fable" / "onyx" / "nova" / "shimmer"
    public let model: String          // "tts-1" or "tts-1-hd"

    private let apiKeyProvider: @Sendable () async throws -> String
    private let session: URLSession

    public init(
        defaultVoice: String = "alloy",
        model: String = "tts-1-hd",
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared
    ) {
        self.defaultVoice = defaultVoice
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

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw TTSError.requestFailed("invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let voice = voiceID ?? defaultVoice
        let body: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": text,
            "response_format": format.openAIName,
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

    /// Streaming — OpenAI returns chunked transfer encoding; we
    /// surface ~4 KB chunks via the async bytes API.
    public nonisolated func synthesizeStream(
        text: String,
        voiceID: String?,
        format: TTSAudioFormat
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await apiKeyProvider()
                    guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
                        throw TTSError.requestFailed("invalid URL")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    let voice = voiceID ?? defaultVoice
                    let body: [String: Any] = [
                        "model": model,
                        "voice": voice,
                        "input": text,
                        "response_format": format.openAIName,
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

    /// OpenAI exposes six voices as fixed identifiers.
    public nonisolated func voices() -> [TTSVoice] {
        ["alloy", "echo", "fable", "onyx", "nova", "shimmer"].map {
            TTSVoice(id: $0, displayName: $0.capitalized)
        }
    }
}

private extension TTSAudioFormat {
    var openAIName: String {
        switch self {
        case .mp3:  return "mp3"
        case .wav:  return "wav"
        case .opus: return "opus"
        case .aac:  return "aac"
        case .pcm:  return "pcm"  // OpenAI exposes raw PCM s16le
        }
    }
}
