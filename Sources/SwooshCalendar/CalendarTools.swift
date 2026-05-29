// SwooshCalendar/CalendarTools.swift — 0.1A Agent-facing calendar tools
//
// Two tools the agent uses to run Detour's calendar:
//   • calendar_list_events  (read,  .detourCalendarRead)
//   • calendar_manage_event (write, .detourCalendarWrite — create/update/remove)
// Dates are passed as ISO8601 strings because tool inputs decode with a plain
// JSONDecoder (no date strategy); they're parsed to absolute Dates here.

import Foundation
import SwooshTools

// MARK: - Dependencies

public struct CalendarToolDependencies: Sendable {
    public let store: FileCalendarStore

    public init(store: FileCalendarStore) {
        self.store = store
    }
}

// MARK: - Shared output

public struct CalendarToolOutput: Codable, Sendable {
    public let events: [CalendarEvent]
    public let message: String
}

// MARK: - List tool (read)

public struct CalendarListInput: Codable, Sendable {
    public let limit: Int?
    public init(limit: Int? = nil) { self.limit = limit }
}

public struct CalendarListTool: SwooshTool {
    public typealias Input = CalendarListInput
    public typealias Output = CalendarToolOutput

    public static let name: ToolName = "calendar_list_events"
    public static let displayName = "List Calendar Events"
    public static let description = "List upcoming events on the user's Detour calendar."
    public static let permission: SwooshPermission = .detourCalendarRead
    public static let risk: ToolRisk = .low
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .calendar

    private let store: FileCalendarStore
    public init(dependencies: CalendarToolDependencies) { self.store = dependencies.store }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let events = try await store.upcoming(limit: input.limit)
        return Output(events: events, message: "\(events.count) upcoming event(s)")
    }
}

// MARK: - Manage tool (write)

public enum CalendarWriteAction: String, Codable, Sendable {
    case create, update, remove
}

public struct CalendarManageInput: Codable, Sendable {
    public let action: CalendarWriteAction
    public let id: String?
    public let title: String?
    /// ISO8601, e.g. "2026-05-29T14:00:00Z".
    public let start: String?
    /// ISO8601. If omitted on create, defaults to one hour after `start`.
    public let end: String?
    public let notes: String?
    public let location: String?

    public init(
        action: CalendarWriteAction,
        id: String? = nil,
        title: String? = nil,
        start: String? = nil,
        end: String? = nil,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.action = action
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.location = location
    }
}

public struct CalendarManageTool: SwooshTool {
    public typealias Input = CalendarManageInput
    public typealias Output = CalendarToolOutput

    public static let name: ToolName = "calendar_manage_event"
    public static let displayName = "Manage Calendar Event"
    public static let description =
        "Create, update, or remove an event on the user's Detour calendar. Dates are ISO8601 (e.g. 2026-05-29T14:00:00Z)."
    public static let permission: SwooshPermission = .detourCalendarWrite
    public static let risk: ToolRisk = .low
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .calendar

    private let store: FileCalendarStore
    public init(dependencies: CalendarToolDependencies) { self.store = dependencies.store }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        switch input.action {
        case .create:
            let title = try input.title.unwrap(or: CalendarToolError.missingField("title"))
            let start = try parseDate(input.start, field: "start")
            let end = try input.end.map { try parse($0, field: "end") } ?? start.addingTimeInterval(3600)
            let event = CalendarEvent(
                title: title, start: start, end: end,
                notes: input.notes, location: input.location)
            try await store.add(event)
            return Output(events: [event], message: "created")

        case .update:
            let id = try input.id.unwrap(or: CalendarToolError.missingField("id"))
            guard var event = try await store.get(id: id) else { throw CalendarStoreError.notFound(id) }
            if let title = input.title { event.title = title }
            if let start = input.start { event.start = try parse(start, field: "start") }
            if let end = input.end { event.end = try parse(end, field: "end") }
            if let notes = input.notes { event.notes = notes }
            if let location = input.location { event.location = location }
            try await store.update(event)
            return Output(events: [event], message: "updated")

        case .remove:
            let id = try input.id.unwrap(or: CalendarToolError.missingField("id"))
            try await store.remove(id: id)
            return Output(events: [], message: "removed")
        }
    }

    private func parseDate(_ value: String?, field: String) throws -> Date {
        try parse(value.unwrap(or: CalendarToolError.missingField(field)), field: field)
    }

    private func parse(_ value: String, field: String) throws -> Date {
        guard let date = CalendarDateParser.date(from: value) else {
            throw CalendarToolError.badDate(field, value)
        }
        return date
    }
}

// MARK: - Date parsing

enum CalendarDateParser {
    static func date(from string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

// MARK: - Errors

public enum CalendarToolError: Error, Sendable, LocalizedError {
    case missingField(String)
    case badDate(String, String)

    public var errorDescription: String? {
        switch self {
        case .missingField(let name): "missing field: \(name)"
        case .badDate(let field, let value): "field \(field) is not a valid ISO8601 date: \(value)"
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
