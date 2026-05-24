// SwooshToolsets/MediaCacheDir.swift — 0.4A Media cache helper
//
// Atomic temp-file writer for media-generation tool outputs. Picks
// `~/.swoosh/media-cache/` on macOS / Linux and the app's Application
// Support directory on iOS so the daemon's tool returns a stable path
// the caller can render or upload.

import Foundation

public enum MediaCacheDir {
    /// Default cache location. On macOS: `~/.swoosh/media-cache/`.
    /// On iOS / sandboxed contexts: `Application Support/ai.swoosh.agent/media-cache/`.
    public static func `default`() -> URL {
        #if os(macOS) || os(Linux)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh", isDirectory: true)
            .appendingPathComponent("media-cache", isDirectory: true)
        #else
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("ai.swoosh.agent", isDirectory: true)
            .appendingPathComponent("media-cache", isDirectory: true)
        #endif
    }

    /// Write `data` to `<dir>/<uuid>.<ext>` atomically. Creates the
    /// directory if missing. Returns the absolute file URL.
    @discardableResult
    public static func write(
        _ data: Data,
        extension ext: String,
        in dir: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Map common video / image MIME types to a sensible file extension.
    /// Unknown types fall back to `fallback`.
    public static func fileExtension(forMime mime: String, fallback: String) -> String {
        let normalized = mime.lowercased()
        switch normalized {
        case "video/mp4":       return "mp4"
        case "video/quicktime": return "mov"
        case "video/webm":      return "webm"
        case "image/png":       return "png"
        case "image/jpeg":      return "jpg"
        case "image/webp":      return "webp"
        case "audio/mpeg":      return "mp3"
        case "audio/wav":       return "wav"
        case "audio/ogg":       return "ogg"
        default:                return fallback
        }
    }
}
