// SwooshDaemon/CalendarAPIBridge.swift — 0.1A Calendar store ↔ HTTP API
//
// The sole translator between the domain `SwooshCalendar.CalendarEvent` and
// the wire `SwooshClient.CalendarEventSummary`. The read endpoint serves the
// agent-managed Detour calendar to the tray/dashboard.

import Foundation
import SwooshAPI
import SwooshClient
import SwooshCalendar

extension SwooshDaemon {

    static func calendarEventSummary(_ event: CalendarEvent) -> CalendarEventSummary {
        CalendarEventSummary(
            id: event.id,
            title: event.title,
            start: event.start,
            end: event.end,
            notes: event.notes,
            location: event.location
        )
    }

    static func calendarEventsAPIResponse(store: any CalendarStoring) async -> CalendarEventsResponse {
        let events = (try? await store.upcoming(limit: nil)) ?? []
        return CalendarEventsResponse(events: events.map(calendarEventSummary))
    }
}
