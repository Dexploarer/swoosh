// SwooshMusic/InlineMusicJob.swift — 0.9R Helper for direct-response music providers
//
// ElevenLabs Music and Stable Audio both return the audio bytes
// directly in the POST response — no job polling. This wraps the
// downloaded file as a `MusicJob` so the calling code stays uniform
// across providers.

import Foundation

struct InlineMusicJob: MusicJob {
    let id: String
    let url: URL
    let modelUsed: String
    let prompt: String

    var result: MusicResult {
        get async throws {
            MusicResult(
                audioURL: url,
                mimeType: "audio/mpeg",
                durationSeconds: nil,
                modelUsed: modelUsed,
                promptEcho: prompt
            )
        }
    }

    func cancel() async {
        // Direct-response — nothing to cancel server-side.
    }
}
