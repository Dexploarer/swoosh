// SwooshManifesting/ManifestationStore.swift — Persistence for manifestations — 0.1A
//
// Same shape as the skill / goal stores — protocol + in-memory default.
// Each manifestation record is the audit trail of one self-improvement
// pass; production runtime writes them through the ActantDB-backed
// conformance once that's wired.

import Foundation

public protocol ManifestationStoring: Sendable {
    func save(_ manifestation: Manifestation) async throws
    func update(_ manifestation: Manifestation) async throws
    func get(id: String) async throws -> Manifestation?
    func listRecent(limit: Int) async throws -> [Manifestation]
    /// Most recent successfully completed pass, if any. Used to compute
    /// the audit window for the next gather phase.
    func mostRecentCompleted() async throws -> Manifestation?
    func delete(id: String) async throws
}

public actor InMemoryManifestationStore: ManifestationStoring {
    private var records: [String: Manifestation] = [:]

    public init() {}

    public func save(_ manifestation: Manifestation) async throws {
        records[manifestation.id] = manifestation
    }

    public func update(_ manifestation: Manifestation) async throws {
        records[manifestation.id] = manifestation
    }

    public func get(id: String) async throws -> Manifestation? {
        records[id]
    }

    public func listRecent(limit: Int) async throws -> [Manifestation] {
        Array(records.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func mostRecentCompleted() async throws -> Manifestation? {
        records.values
            .filter { $0.status == .completed }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .first
    }

    public func delete(id: String) async throws {
        records.removeValue(forKey: id)
    }
}

public actor FileManifestationStore: ManifestationStoring {
    private let url: URL
    private var loaded = false
    private var records: [String: Manifestation] = [:]

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/manifesting/manifestations.json")
    }

    public func save(_ manifestation: Manifestation) throws {
        try ensureLoaded()
        records[manifestation.id] = manifestation
        try persist()
    }

    public func update(_ manifestation: Manifestation) throws {
        try ensureLoaded()
        records[manifestation.id] = manifestation
        try persist()
    }

    public func get(id: String) throws -> Manifestation? {
        try ensureLoaded()
        return records[id]
    }

    public func listRecent(limit: Int) throws -> [Manifestation] {
        try ensureLoaded()
        return Array(records.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func mostRecentCompleted() throws -> Manifestation? {
        try ensureLoaded()
        return records.values
            .filter { $0.status == .completed }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .first
    }

    public func delete(id: String) throws {
        try ensureLoaded()
        guard records.removeValue(forKey: id) != nil else { return }
        try persist()
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder.swooshManifesting.decode(ManifestationStoreSnapshot.self, from: data)
            records = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        }
        loaded = true
    }

    private func persist() throws {
        let snapshot = ManifestationStoreSnapshot(records: records.values.sorted { $0.startedAt > $1.startedAt })
        let data = try JSONEncoder.swooshManifesting.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

private struct ManifestationStoreSnapshot: Codable, Sendable {
    let records: [Manifestation]
}

private extension JSONEncoder {
    static var swooshManifesting: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var swooshManifesting: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
