// SwooshClient/SwooshAPIClient+Calendar.swift — 0.1A Calendar read endpoint
//
// Wire method for `GET /api/calendar/events`. The tray/dashboard read the
// Detour calendar through this; writes happen via the agent's calendar tools.

import Foundation

extension SwooshAPIClient {
    public func calendarEvents() async throws -> CalendarEventsResponse {
        let request = try makeRequest(method: "GET", path: "api/calendar/events", body: nil)
        return try await execute(request, as: CalendarEventsResponse.self)
    }
}
