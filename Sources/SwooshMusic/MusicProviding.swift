// SwooshMusic/MusicProviding.swift — 0.9R Music-gen provider protocol
//
// Music generation is typically long-running — providers return a
// job id, then the caller polls (or webhooks) until the track is
// ready. Our protocol exposes both shapes: `generate(...)` returns a
// `MusicJob`; the caller awaits its `.result` async property.
//
// Built-in providers (this module):
//   • Suno              — POST /v2/generate, GET /v2/generate/{id}
//   • ElevenLabs Music  — POST /v1/music, GET /v1/music/{id}
//   • Stable Audio      — Stability AI's /v2beta/audio/stable-audio-2

import Foundation

public protocol MusicProviding: Sendable {

    var displayName: String { get }
    var id: String { get }

    /// Available models the provider exposes for music generation
    /// (e.g. Suno v3.5 vs v4, ElevenLabs Music v1).
    var availableModels: [MusicModel] { get }

    /// Kick off a generation job. Returns a `MusicJob` whose `.result`
    /// awaits until the track is ready (or throws on failure).
    func generate(_ request: MusicRequest) async throws -> MusicJob
}

public struct MusicRequest: Sendable {
    public let prompt: String
    public let model: String?
    public let durationSeconds: Double?
    public let style: String?
    public let lyrics: String?
    public let instrumentalOnly: Bool

    public init(
        prompt: String,
        model: String? = nil,
        durationSeconds: Double? = nil,
        style: String? = nil,
        lyrics: String? = nil,
        instrumentalOnly: Bool = false
    ) {
        self.prompt = prompt
        self.model = model
        self.durationSeconds = durationSeconds
        self.style = style
        self.lyrics = lyrics
        self.instrumentalOnly = instrumentalOnly
    }
}

public struct MusicModel: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let maxDuration: Double

    public init(id: String, displayName: String, maxDuration: Double) {
        self.id = id
        self.displayName = displayName
        self.maxDuration = maxDuration
    }
}

/// One in-flight music-gen job. Use `await job.result` to wait for
/// completion. `progress` is an optional stream of [0,1] updates.
public protocol MusicJob: Sendable {
    var id: String { get }
    var result: MusicResult { get async throws }
    /// Cancel the job if the provider supports it.
    func cancel() async
}

public struct MusicResult: Sendable {
    public let audioURL: URL          // Remote URL to the rendered MP3/WAV
    public let mimeType: String
    public let durationSeconds: Double?
    public let modelUsed: String
    public let promptEcho: String?

    public init(
        audioURL: URL,
        mimeType: String,
        durationSeconds: Double? = nil,
        modelUsed: String,
        promptEcho: String? = nil
    ) {
        self.audioURL = audioURL
        self.mimeType = mimeType
        self.durationSeconds = durationSeconds
        self.modelUsed = modelUsed
        self.promptEcho = promptEcho
    }
}

public enum MusicError: Error, CustomStringConvertible {
    case missingAPIKey(String)
    case requestFailed(String)
    case jobFailed(String)
    case timeout(String)

    public var description: String {
        switch self {
        case .missingAPIKey(let p):  return "Missing API key for \(p)."
        case .requestFailed(let m):  return "Music request failed: \(m)"
        case .jobFailed(let m):      return "Music job failed: \(m)"
        case .timeout(let m):        return "Music job timed out: \(m)"
        }
    }
}
