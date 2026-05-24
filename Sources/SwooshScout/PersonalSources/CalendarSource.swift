// SwooshScout/PersonalSources/CalendarSource.swift — 0.9S Calendar cadence (aggregate-only)
//
// EventKit-backed calendar source. **Deliberately anonymous** — emits
// aggregate cadence patterns, not titles or attendees. The candidate
// generator turns these into "User has standing meetings on Wednesday
// afternoons" memories, never "Meeting with Alice." This file MUST
// stay aggregate-only — see module CLAUDE.md "Aggregate-only sources".

import Foundation
#if canImport(EventKit)
import EventKit
#endif

public struct CalendarSource: ScoutSource {
    public let id = "calendar"
    public let displayName = "Calendar"
    public let description = "Recent and upcoming calendar density. Titles and attendees are not exported."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["calendar.read"]

    public let pastDays: Int
    public let futureDays: Int

    public init(pastDays: Int = 14, futureDays: Int = 14) {
        self.pastDays = pastDays
        self.futureDays = futureDays
    }

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if canImport(EventKit)
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        case .writeOnly: return .denied
        @unknown default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        #if canImport(EventKit)
        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = (try? await store.requestAccess(to: .event)) ?? false
        }
        return granted ? .granted : .denied
        #else
        return .denied
        #endif
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(EventKit)
        let store = EKEventStore()
        let start = Calendar.current.date(byAdding: .day, value: -pastDays, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: futureDays, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        // Aggregate by weekday and hour bucket. Title-free.
        var weekdayCount: [Int: Int] = [:]
        var hourCount: [Int: Int] = [:]
        var totalDuration: TimeInterval = 0
        for event in events {
            let weekday = Calendar.current.component(.weekday, from: event.startDate)
            let hour = Calendar.current.component(.hour, from: event.startDate)
            weekdayCount[weekday, default: 0] += 1
            hourCount[hour, default: 0] += 1
            totalDuration += event.endDate.timeIntervalSince(event.startDate)
        }

        let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let busiestWeekday = weekdayCount.max { $0.value < $1.value }
            .map { weekdayNames[($0.key - 1) % 7] }
        let busiestHour = hourCount.max { $0.value < $1.value }.map { $0.key }

        var records: [ScoutRecord] = []
        records.append(ScoutRecord(
            sourceID: id, kind: .calendarPattern, sensitivity: .medium,
            content: "Calendar density: \(events.count) events across the window.",
            metadata: [
                "events": String(events.count),
                "total_minutes": String(Int(totalDuration / 60)),
                "past_days": String(pastDays),
                "future_days": String(futureDays)
            ]
        ))
        if let weekday = busiestWeekday {
            records.append(ScoutRecord(
                sourceID: id, kind: .calendarPattern, sensitivity: .medium,
                content: "Busiest weekday for meetings: \(weekday).",
                metadata: ["weekday": weekday]
            ))
        }
        if let hour = busiestHour {
            records.append(ScoutRecord(
                sourceID: id, kind: .calendarPattern, sensitivity: .medium,
                content: "Most meetings cluster around \(String(format: "%02d:00", hour)) local.",
                metadata: ["hour": String(hour)]
            ))
        }
        return records
        #else
        return []
        #endif
    }
}
