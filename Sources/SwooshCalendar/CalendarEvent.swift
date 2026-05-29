// SwooshCalendar/CalendarEvent.swift — 0.1A Detour calendar domain model
//
// The event record for Detour's own agent-managed calendar. This is NOT
// Apple Calendar / EventKit and NOT SwooshScout's aggregate CalendarSource —
// it's a first-class store the agent reads and writes via tool calls. Dates
// are absolute instants; the store persists them ISO8601.

import Foundation

public struct CalendarEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String?
    public var location: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        start: Date,
        end: Date,
        notes: String? = nil,
        location: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
