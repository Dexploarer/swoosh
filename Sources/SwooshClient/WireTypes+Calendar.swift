// SwooshClient/WireTypes+Calendar.swift — 0.1A Calendar wire types
//
// Stable wire projection of a Detour calendar event for `GET
// /api/calendar/events`. Standalone (SwooshClient has zero domain deps);
// the daemon maps its domain `SwooshCalendar.CalendarEvent` into this in
// `CalendarAPIBridge.swift`.

import Foundation

public struct CalendarEventSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let notes: String?
    public let location: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
    }
}

public struct CalendarEventsResponse: Codable, Sendable {
    public let events: [CalendarEventSummary]

    public init(events: [CalendarEventSummary]) {
        self.events = events
    }
}
