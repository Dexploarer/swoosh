// SwooshScout/PersonalizationSignals.swift — 0.9S Passive personalization signals
//
// Append-only JSONL signal store the daemon writes while running.
// `PersonalizationSignalSource` reads the store on demand and emits
// aggregate `personalizationSignal` records — never the raw signal
// stream — so the model never sees individual app-focus events.

import Foundation

public enum PersonalizationSignalKind: String, Codable, Sendable {
    case daemonStarted = "daemon_started"
    case appFocus = "app_focus"
    case scoutAutopilotRun = "scout_autopilot_run"
}

public struct PersonalizationSignal: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: PersonalizationSignalKind
    public let label: String
    public let occurredAt: Date
    public let weight: Double
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        kind: PersonalizationSignalKind,
        label: String,
        occurredAt: Date = Date(),
        weight: Double = 1,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.occurredAt = occurredAt
        self.weight = weight
        self.metadata = metadata
    }
}

public actor PersonalizationSignalStore {
    public let url: URL
    public let maxBytes: Int

    public init(
        url: URL = PersonalizationSignalStore.defaultURL(),
        maxBytes: Int = 2 * 1024 * 1024
    ) {
        self.url = url
        self.maxBytes = maxBytes
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/personalization-signals.jsonl", isDirectory: false)
    }

    public func append(_ signal: PersonalizationSignal) async throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(signal) + Data("\n".utf8)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
        try rotateIfNeeded()
    }

    public func recent(since cutoff: Date) async throws -> [PersonalizationSignal] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let lineData = String(line).data(using: .utf8),
                  let signal = try? decoder.decode(PersonalizationSignal.self, from: lineData),
                  signal.occurredAt >= cutoff else { return nil }
            return signal
        }
    }

    private func ensureDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private func rotateIfNeeded() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? Int, size > maxBytes else { return }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.dropFirst(max(1, lines.count / 4)).joined(separator: "\n")
        try kept.write(to: url, atomically: true, encoding: .utf8)
    }
}

public struct PersonalizationSignalSource: ScoutSource {
    public let id = "personalization_signals"
    public let displayName = "Passive Personalization Signals"
    public let description = "Aggregate Swoosh runtime signals collected while the daemon runs."
    public let sensitivity = Sensitivity.low
    public let requiredPermissions: [String] = []

    public let store: PersonalizationSignalStore
    public let window: TimeInterval

    public init(
        store: PersonalizationSignalStore = PersonalizationSignalStore(),
        window: TimeInterval = 14 * 24 * 60 * 60
    ) {
        self.store = store
        self.window = window
    }

    public func checkPermission() async throws -> SourcePermissionStatus { .granted }

    public func requestPermission() async throws -> SourcePermissionStatus { .granted }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        let cutoff = Date().addingTimeInterval(-window)
        let signals = try await store.recent(since: cutoff)
        var groups: [String: (kind: PersonalizationSignalKind, label: String, count: Int, weight: Double, last: Date)] = [:]
        for signal in signals {
            let groupKey = "\(signal.kind.rawValue)|\(signal.label.lowercased())"
            var group = groups[groupKey] ?? (signal.kind, signal.label, 0, 0, .distantPast)
            group.count += 1
            group.weight += signal.weight
            group.last = max(group.last, signal.occurredAt)
            groups[groupKey] = group
        }

        return groups.values.sorted { lhs, rhs in
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
            return lhs.label < rhs.label
        }.map { group in
            ScoutRecord(
                sourceID: id,
                kind: .personalizationSignal,
                sensitivity: .low,
                content: "\(group.label): \(group.count) event(s), weight \(String(format: "%.1f", group.weight))",
                metadata: [
                    "signal_kind": group.kind.rawValue,
                    "count": String(group.count),
                    "weight": String(format: "%.2f", group.weight),
                    "last_seen": ISO8601DateFormatter().string(from: group.last),
                    "window_days": String(Int(window / 86400)),
                ]
            )
        }
    }
}
