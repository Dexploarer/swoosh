// SwooshLocalVoice/LocalVoiceCloneStore.swift — 0.9R Persistent voice clones
//
// File-backed actor that persists FluidAudio `PocketTtsVoiceData` blobs
// keyed by user-chosen name. One enroll per recording, then reuse the
// stored data for every future synth — no re-extraction of the reference.
//
// On-disk layout:
//   <appSupport>/ai.swoosh.voiceclones/
//     ├── <name-slug>.voicedata     (Codable PocketTtsVoiceData)
//     └── <name-slug>.reference.wav (original recording, optional)
//
// Cross-platform actor — no UI deps — so tests on macOS exercise the
// full round-trip without an iOS host.

import Foundation
#if os(iOS)
import FluidAudio
#endif

/// A persisted voice clone — name + path to the enrollment blob + the
/// original reference recording (kept for re-enrollment / playback).
public struct VoiceCloneRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: String           // slug derived from name; stable across launches
    public let name: String         // user-facing label
    public let createdAt: Date
    public let referenceURL: URL?   // original audio, if retained
    public let durationSeconds: Double?

    public init(
        id: String,
        name: String,
        createdAt: Date = .now,
        referenceURL: URL? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.referenceURL = referenceURL
        self.durationSeconds = durationSeconds
    }
}

public actor LocalVoiceCloneStore {

    public static let shared = LocalVoiceCloneStore()

    /// Captured at init so `voiceDataURL(id:)` can stay nonisolated. URL is
    /// Sendable and this value is never mutated after construction.
    private nonisolated let root: URL
    private var index: [String: VoiceCloneRecord] = [:]
    private var loaded = false

    public init(root: URL = LocalVoiceCloneStore.defaultRoot()) {
        self.root = root
    }

    /// Default on-disk location: app Application Support dir, or temp
    /// when AppSupport is unavailable (e.g. test hosts with no entitlement).
    public static func defaultRoot() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("ai.swoosh.voiceclones", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Index

    /// Load the on-disk index. Safe to call repeatedly — subsequent calls no-op.
    public func loadIndex() throws {
        if loaded { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let indexURL = root.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            let records = try JSONDecoder().decode([VoiceCloneRecord].self, from: data)
            index = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        }
        loaded = true
    }

    public func all() throws -> [VoiceCloneRecord] {
        try loadIndex()
        return index.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func record(named id: String) throws -> VoiceCloneRecord? {
        try loadIndex()
        return index[id]
    }

    // MARK: - Enrollment

    /// Save a new clone. The caller passes the already-encoded voice
    /// data blob plus optional reference audio. Returns the persisted
    /// record so the UI can refresh.
    public func add(
        name: String,
        voiceDataBytes: Data,
        referenceAudio: URL? = nil,
        durationSeconds: Double? = nil
    ) throws -> VoiceCloneRecord {
        try loadIndex()
        let id = try uniqueID(from: name)
        let blobURL = root.appendingPathComponent("\(id).voicedata")
        try voiceDataBytes.write(to: blobURL, options: .atomic)

        // Copy the reference audio into the clone dir so deleting the
        // original doesn't break re-enrollment.
        var storedRef: URL? = nil
        if let referenceAudio {
            let dest = root.appendingPathComponent("\(id).reference.wav")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: referenceAudio, to: dest)
            storedRef = dest
        }

        let record = VoiceCloneRecord(
            id: id, name: name, referenceURL: storedRef,
            durationSeconds: durationSeconds
        )
        index[id] = record
        try writeIndex()
        return record
    }

    public func delete(id: String) throws {
        try loadIndex()
        index.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("\(id).voicedata"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("\(id).reference.wav"))
        try writeIndex()
    }

    /// Bytes of the persisted voice data blob, ready to feed into a
    /// cloning backend (e.g. PocketTtsVoiceData decode + synthesize).
    public func voiceDataBytes(id: String) throws -> Data? {
        let url = root.appendingPathComponent("\(id).voicedata")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// URL of the persisted voice data blob; useful for backends that
    /// prefer URL-based decode (no double-copy of large enrollment blobs).
    public nonisolated func voiceDataURL(id: String) -> URL {
        root.appendingPathComponent("\(id).voicedata")
    }

    /// URL of the stored reference audio (if any), for playback preview.
    public func referenceAudioURL(id: String) throws -> URL? {
        try loadIndex()
        return index[id]?.referenceURL
    }

    // MARK: - Internals

    /// Returns a slug that doesn't already exist in the index OR on
    /// disk. Defends against orphan blobs from partial prior writes.
    private func uniqueID(from name: String) throws -> String {
        let base = Self.slug(from: name)
        if !exists(id: base) { return base }
        for suffix in 1..<1000 {
            let candidate = "\(base)-\(suffix)"
            if !exists(id: candidate) { return candidate }
        }
        throw LocalVoiceError.modelLoadFailed(
            "Could not allocate a unique clone id for \(name)"
        )
    }

    private func exists(id: String) -> Bool {
        if index[id] != nil { return true }
        return FileManager.default.fileExists(
            atPath: root.appendingPathComponent("\(id).voicedata").path
        )
    }

    private func writeIndex() throws {
        let indexURL = root.appendingPathComponent("index.json")
        let payload = Array(index.values)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: indexURL, options: .atomic)
    }

    /// Slug derived from a human-typed name. Stable across launches
    /// (lowercased, ASCII, spaces → "-", strips other punctuation,
    /// no leading/trailing dashes).
    static func slug(from name: String) -> String {
        let lower = name.lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in lower.unicodeScalars {
            if (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) {
                out.append(Character(scalar))
                lastWasDash = false
            } else if scalar == " " || scalar == "_" || scalar == "-" {
                if !lastWasDash, !out.isEmpty {
                    out.append("-")
                    lastWasDash = true
                }
            }
            // other characters dropped
        }
        // Trim trailing dash so "trim  spaces  " → "trim-spaces".
        while out.hasSuffix("-") { out.removeLast() }
        if out.isEmpty { return "voice-\(UUID().uuidString.prefix(8).lowercased())" }
        return out
    }
}
