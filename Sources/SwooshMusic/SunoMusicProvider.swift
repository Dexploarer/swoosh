// SwooshMusic/SunoMusicProvider.swift — 0.9R Suno via sunoapi.org gateway
//
// Suno Inc. itself does not publish a third-party API as of May 2026.
// The de facto integration is **sunoapi.org**, a third-party gateway
// that's the most-documented and most-cited path; it ships a versioned
// OpenAPI spec and current model coverage through V5_5.
//
// Sources:
//   • https://docs.sunoapi.org/
//   • https://docs.sunoapi.org/suno-api/generate-music
//   • https://docs.sunoapi.org/suno-api/get-music-generation-details
//
// Endpoints:
//   POST https://api.sunoapi.org/api/v1/generate
//   GET  https://api.sunoapi.org/api/v1/generate/record-info?taskId={id}
//
// Required body fields: customMode, instrumental, model, callBackUrl
// (server demands it even if you intend to poll — give it a sink).
//
// Models: V4, V4_5, V4_5PLUS, V4_5ALL, V5, V5_5 (V5.5 shipped 2026-03-25).
//
// Status enum: PENDING → TEXT_SUCCESS → FIRST_SUCCESS → SUCCESS
// Failure states: CREATE_TASK_FAILED · GENERATE_AUDIO_FAILED ·
//                 CALLBACK_EXCEPTION · SENSITIVE_WORD_ERROR.

import Foundation

public actor SunoMusicProvider: MusicProviding {

    public nonisolated let displayName = "Suno"
    public nonisolated let id = "suno"

    public nonisolated let availableModels: [MusicModel] = [
        MusicModel(id: "V5_5",     displayName: "Suno V5.5 (latest)", maxDuration: 240),
        MusicModel(id: "V5",       displayName: "Suno V5",            maxDuration: 240),
        MusicModel(id: "V4_5PLUS", displayName: "Suno V4.5+",         maxDuration: 240),
        MusicModel(id: "V4_5",     displayName: "Suno V4.5",          maxDuration: 240),
        MusicModel(id: "V4",       displayName: "Suno V4",            maxDuration: 240),
    ]

    private let apiKeyProvider: @Sendable () async throws -> String
    private let host: URL
    private let session: URLSession

    /// `callbackURL` is required by sunoapi.org even when you're polling.
    /// Any reachable URL works (it just won't be used). Pass nil to use
    /// the default sink URL embedded in this file.
    private let callbackURL: URL

    public init(
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        host: URL = URL(string: "https://api.sunoapi.org")!,
        callbackURL: URL = URL(string: "https://example.invalid/suno-callback")!,
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.host = host
        self.callbackURL = callbackURL
        self.session = session
    }

    public func generate(_ request: MusicRequest) async throws -> MusicJob {
        let apiKey: String
        do { apiKey = try await apiKeyProvider() }
        catch { throw MusicError.missingAPIKey(displayName) }

        // Per sunoapi.org spec: customMode + instrumental + model + callBackUrl
        // are always required. customMode=true unlocks style/title/lyrics.
        let useCustom = request.style != nil || request.lyrics != nil
        var body: [String: Any] = [
            "customMode": useCustom,
            "instrumental": request.instrumentalOnly,
            "model": request.model ?? "V5_5",
            "callBackUrl": callbackURL.absoluteString,
            "prompt": request.prompt,
        ]
        if useCustom {
            if let style = request.style { body["style"] = style }
            if let lyrics = request.lyrics { body["lyrics"] = lyrics }
        }

        var req = URLRequest(url: host.appendingPathComponent("api/v1/generate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        MusicLogger.suno.info("submitting generation model=\(request.model ?? "V5_5", privacy: .public) customMode=\(useCustom)")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? ""
            MusicLogger.suno.error("generate failed HTTP \(status): \(preview, privacy: .public)")
            throw MusicError.requestFailed("HTTP \(status): \(preview)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any],
              let taskID = inner["taskId"] as? String else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            MusicLogger.suno.error("missing data.taskId — preview: \(preview, privacy: .public)")
            throw MusicError.requestFailed("missing data.taskId — got: \(preview)")
        }
        MusicLogger.suno.info("taskId=\(taskID, privacy: .public)")
        return SunoMusicJob(
            id: taskID,
            host: host,
            apiKey: apiKey,
            modelUsed: (request.model ?? "V5_5"),
            prompt: request.prompt,
            session: session
        )
    }
}

private final class SunoMusicJob: MusicJob, @unchecked Sendable {
    let id: String
    private let host: URL
    private let apiKey: String
    private let modelUsed: String
    private let prompt: String
    private let session: URLSession
    private var cancelled = false

    init(
        id: String,
        host: URL,
        apiKey: String,
        modelUsed: String,
        prompt: String,
        session: URLSession
    ) {
        self.id = id
        self.host = host
        self.apiKey = apiKey
        self.modelUsed = modelUsed
        self.prompt = prompt
        self.session = session
    }

    var result: MusicResult {
        get async throws {
            // Suno generates in ~30-90s typically; we poll up to 5 min.
            for _ in 0..<60 {
                if cancelled { throw MusicError.jobFailed("cancelled") }
                let info = try await pollOnce()
                if info.terminal {
                    if let url = info.audioURL {
                        return MusicResult(
                            audioURL: url,
                            mimeType: "audio/mpeg",
                            durationSeconds: info.duration,
                            modelUsed: modelUsed,
                            promptEcho: prompt
                        )
                    }
                    throw MusicError.jobFailed("status=\(info.status)")
                }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            throw MusicError.timeout("Suno taskId \(id) did not finish within 5 min")
        }
    }

    func cancel() async {
        cancelled = true
    }

    private struct Status {
        let status: String
        let audioURL: URL?
        let duration: Double?
        /// True for any state that should stop the poll loop (success or failure).
        var terminal: Bool {
            status == "SUCCESS"
                || status == "CREATE_TASK_FAILED"
                || status == "GENERATE_AUDIO_FAILED"
                || status == "CALLBACK_EXCEPTION"
                || status == "SENSITIVE_WORD_ERROR"
        }
    }

    private func pollOnce() async throws -> Status {
        var comps = URLComponents(url: host.appendingPathComponent("api/v1/generate/record-info"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "taskId", value: id)]
        guard let url = comps.url else { throw MusicError.requestFailed("bad poll URL") }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any] else {
            throw MusicError.requestFailed("invalid poll response")
        }
        let status = (inner["status"] as? String) ?? "UNKNOWN"
        // Audio URL lives at data.response.sunoData[0].audioUrl
        var audioURL: URL? = nil
        if let resp = inner["response"] as? [String: Any],
           let arr = resp["sunoData"] as? [[String: Any]],
           let first = arr.first,
           let urlStr = first["audioUrl"] as? String {
            audioURL = URL(string: urlStr)
        }
        let duration = (inner["duration"] as? Double)
        return Status(status: status, audioURL: audioURL, duration: duration)
    }
}
