// SwooshScout/PersonalSources/RemindersSource.swift — 0.9S Reminders backlog (aggregate-only)
//
// EventKit reminders source. Emits load and completion-rate patterns,
// not item titles. "User typically has ~12 open reminders" is fine;
// "User has reminder 'call mom'" is not. Same aggregate-only contract
// as `CalendarSource`.

import Foundation
#if canImport(EventKit)
import EventKit
#endif

public struct RemindersSource: ScoutSource {
    public let id = "reminders"
    public let displayName = "Reminders"
    public let description = "Reminder backlog size and completion cadence. Reminder text is not exported."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["reminders.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if canImport(EventKit)
        switch EKEventStore.authorizationStatus(for: .reminder) {
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
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = (try? await store.requestAccess(to: .reminder)) ?? false
        }
        return granted ? .granted : .denied
        #else
        return .denied
        #endif
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(EventKit)
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        // Project to a Sendable tuple inside the callback so we don't
        // smuggle `[EKReminder]` across the continuation boundary
        // (EKReminder isn't Sendable under Swift 6 strict concurrency).
        let counts: (open: Int, overdue: Int) = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { results in
                let items = results ?? []
                let now = Date()
                let overdueCount = items.reduce(into: 0) { acc, item in
                    if let due = item.dueDateComponents?.date, due < now { acc += 1 }
                }
                continuation.resume(returning: (items.count, overdueCount))
            }
        }

        return [
            ScoutRecord(
                sourceID: id, kind: .reminderSummary, sensitivity: .medium,
                content: "Open reminders: \(counts.open) (overdue: \(counts.overdue)).",
                metadata: [
                    "open": String(counts.open),
                    "overdue": String(counts.overdue)
                ]
            )
        ]
        #else
        return []
        #endif
    }
}
