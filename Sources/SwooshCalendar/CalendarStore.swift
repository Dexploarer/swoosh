// SwooshCalendar/CalendarStore.swift — 0.1A Atomic file-backed calendar storage
//
// Mirrors SwooshCron's FileCronJobStore: an actor that loads once, mutates
// in memory, and persists atomically to ~/.swoosh/calendar/events.json. The
// same instance is shared by the agent's calendar tools (write path) and the
// daemon's read API (UI path) — construct it once at daemon startup.

import Foundation

public protocol CalendarStoring: Sendable {
    func add(_ event: CalendarEvent) async throws
    func update(_ event: CalendarEvent) async throws
    func get(id: String) async throws -> CalendarEvent?
    func remove(id: String) async throws
    func list() async throws -> [CalendarEvent]
    func upcoming(limit: Int?) async throws -> [CalendarEvent]
}

public actor FileCalendarStore: CalendarStoring {
    private let eventsURL: URL
    private var loaded = false
    private var events: [String: CalendarEvent] = [:]

    public init(root: URL? = nil) {
        let base = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swoosh/calendar", isDirectory: true)
        self.eventsURL = base.appendingPathComponent("events.json")
    }

    public func add(_ event: CalendarEvent) async throws {
        try ensureLoaded()
        events[event.id] = event
        try persist()
    }

    public func update(_ event: CalendarEvent) async throws {
        try ensureLoaded()
        guard events[event.id] != nil else { throw CalendarStoreError.notFound(event.id) }
        var updated = event
        updated.updatedAt = Date()
        events[event.id] = updated
        try persist()
    }

    public func get(id: String) async throws -> CalendarEvent? {
        try ensureLoaded()
        return events[id]
    }

    public func remove(id: String) async throws {
        try ensureLoaded()
        guard events.removeValue(forKey: id) != nil else { throw CalendarStoreError.notFound(id) }
        try persist()
    }

    public func list() async throws -> [CalendarEvent] {
        try ensureLoaded()
        return events.values.sorted { $0.start < $1.start }
    }

    public func upcoming(limit: Int? = nil) async throws -> [CalendarEvent] {
        let now = Date()
        let future = try await list().filter { $0.end >= now }
        if let limit { return Array(future.prefix(limit)) }
        return future
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(
            at: eventsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            let data = try Data(contentsOf: eventsURL)
            let snapshot = try JSONDecoder.swooshCalendar.decode(CalendarStoreSnapshot.self, from: data)
            events = Dictionary(uniqueKeysWithValues: snapshot.events.map { ($0.id, $0) })
        }
        loaded = true
    }

    private func persist() throws {
        let snapshot = CalendarStoreSnapshot(
            events: events.values.sorted { $0.start < $1.start })
        let data = try JSONEncoder.swooshCalendar.encode(snapshot)
        try data.write(to: eventsURL, options: .atomic)
    }
}

private struct CalendarStoreSnapshot: Codable {
    let events: [CalendarEvent]
}

public enum CalendarStoreError: Error, Sendable, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "calendar event not found: \(id)"
        }
    }
}

extension JSONEncoder {
    static var swooshCalendar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var swooshCalendar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
