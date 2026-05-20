// SwooshManifesting/ManifestationStore.swift — Persistence for manifestations
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
}
