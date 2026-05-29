// Tests/SwooshCalendarTests/CalendarStoreTests.swift — 0.1A
//
// Pins the Detour calendar store + agent tools: persistence round-trips,
// upcoming() filters the past, remove() deletes, and the write tool parses
// ISO8601 input into a stored event. Uses a throwaway temp dir per test.

import Testing
import Foundation
@testable import SwooshCalendar
import SwooshTools

@Suite("FileCalendarStore + tools")
struct CalendarStoreTests {

    private func tempStore() -> FileCalendarStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cal-\(UUID().uuidString)", isDirectory: true)
        return FileCalendarStore(root: dir)
    }

    @Test("add + list round-trips an event")
    func addList() async throws {
        let store = tempStore()
        let now = Date()
        try await store.add(CalendarEvent(title: "Focus", start: now, end: now.addingTimeInterval(3600)))
        let all = try await store.list()
        #expect(all.count == 1)
        #expect(all.first?.title == "Focus")
    }

    @Test("upcoming filters out past events")
    func upcoming() async throws {
        let store = tempStore()
        try await store.add(CalendarEvent(title: "Past",
            start: Date().addingTimeInterval(-7200), end: Date().addingTimeInterval(-3600)))
        try await store.add(CalendarEvent(title: "Future",
            start: Date().addingTimeInterval(3600), end: Date().addingTimeInterval(7200)))
        let up = try await store.upcoming(limit: nil)
        #expect(up.count == 1)
        #expect(up.first?.title == "Future")
    }

    @Test("remove deletes the event")
    func remove() async throws {
        let store = tempStore()
        let e = CalendarEvent(title: "X", start: Date(), end: Date().addingTimeInterval(60))
        try await store.add(e)
        try await store.remove(id: e.id)
        #expect(try await store.list().isEmpty)
    }

    @Test("manage tool creates an event from ISO8601 input")
    func toolCreate() async throws {
        let store = tempStore()
        let tool = CalendarManageTool(dependencies: .init(store: store))
        let out = try await tool.call(
            CalendarManageInput(action: .create, title: "Standup",
                                start: "2026-06-01T09:00:00Z", end: "2026-06-01T09:30:00Z"),
            context: ToolContext(sessionID: "test"))
        #expect(out.events.count == 1)
        #expect(out.message == "created")
        #expect(try await store.list().count == 1)
    }

    @Test("list tool returns upcoming events")
    func toolList() async throws {
        let store = tempStore()
        try await store.add(CalendarEvent(title: "Soon",
            start: Date().addingTimeInterval(600), end: Date().addingTimeInterval(1200)))
        let tool = CalendarListTool(dependencies: .init(store: store))
        let out = try await tool.call(CalendarListInput(limit: nil), context: ToolContext(sessionID: "test"))
        #expect(out.events.count == 1)
        #expect(out.events.first?.title == "Soon")
    }
}
