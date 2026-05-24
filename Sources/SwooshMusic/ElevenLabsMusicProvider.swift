// SwooshMusic/ElevenLabsMusicProvider.swift — 0.9S ElevenLabs Music
//
// ElevenLabs shipped music generation alongside their TTS. Their music
// API takes a text prompt and returns audio directly — no separate
// job polling needed for shorter clips.
//
// Endpoint: POST /v1/music
//
// Optional `firewall` + `auditLog` enforce `.musicGenerate` permission
// and emit `AuditEntry` records around every generation request. The
// iOS picker path passes nil; daemon-side tool wrappers pass real impls.
// The registry-mounted `GenerateMusicTool` is the primary gate; these
// injections are defense-in-depth for direct (non-registry) callers.

import Foundation
import SwooshTools

public actor ElevenLabsMusicProvider: MusicProviding {

    public nonisolated let displayName = "ElevenLabs Music"
    public nonisolated let id = "elevenlabs-music"
    public nonisolated let availableModels: [MusicModel] = [
        MusicModel(id: "music_v1", displayName: "ElevenLabs Music v1", maxDuration: 60),
    ]

    private let apiKeyProvider: @Sendable () async throws -> String
    private let session: URLSession
    private let firewall: (any Firewall)?
    private let auditLog: (any AuditLogging)?

    public init(
        apiKeyProvider: @escaping @Sendable () async throws -> String,
        session: URLSession = .shared,
        firewall: (any Firewall)? = nil,
        auditLog: (any AuditLogging)? = nil
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.firewall = firewall
        self.auditLog = auditLog
    }

    private func audit(_ kind: AuditEntryKind, _ detail: String, success: Bool = true) async {
        guard let auditLog else { return }
        try? await auditLog.append(AuditEntry(
            kind: kind, toolName: id, detail: detail, success: success
        ))
    }

    private func requirePermission() async throws {
        guard let firewall else { return }
        do {
            try await firewall.require(.musicGenerate)
        } catch {
            await audit(.toolCallDenied, "denied", success: false)
            throw error
        }
    }

    public func generate(_ request: MusicRequest) async throws -> MusicJob {
        try await requirePermission()
        let promptHash = String(request.prompt.hash, radix: 16)
        await audit(
            .toolCallStarted,
            "model=\(request.model ?? "music_v1") promptHash=\(promptHash)"
        )

        let apiKey: String
        do { apiKey = try await apiKeyProvider() }
        catch {
            await audit(.toolCallFailed, "missing API key", success: false)
            throw MusicError.missingAPIKey(displayName)
        }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/music") else {
            await audit(.toolCallFailed, "invalid URL", success: false)
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
            await audit(.toolCallFailed, "HTTP \(status)", success: false)
            throw MusicError.requestFailed("HTTP \(status): \(preview)")
        }
        // Direct response — write to a temp file and return its URL.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("elevenlabs-music-\(UUID().uuidString).mp3")
        try data.write(to: tmp)
        await audit(.toolCallSucceeded, "bytes=\(data.count)")
        return InlineMusicJob(
            id: tmp.lastPathComponent,
            url: tmp,
            modelUsed: request.model ?? "music_v1",
            prompt: request.prompt
        )
    }
}
