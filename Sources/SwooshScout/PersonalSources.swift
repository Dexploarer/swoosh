// SwooshScout/PersonalSources.swift — Deep-personalization Scout sources
//
// The "really personal" layer. Every source here:
//   • declares a high sensitivity so the pipeline gates it behind `.deep`
//     personalization,
//   • routes through the system's native auth flow (EventKit / HealthKit /
//     Intents / etc.) and reports `.denied` when the user said no,
//   • produces aggregated records, never raw quotes of personal content.
//     Calendar titles, reminder text, and media titles do not appear in
//     the records the candidate generator sees.
//
// Trust contract holds: scout records → memory candidates → user review
// → durable memory. None of this enters the agent's prompt until the
// user explicitly approves a candidate.

import Foundation
#if canImport(EventKit)
import EventKit
#endif
#if canImport(Intents)
import Intents
#endif
#if canImport(HealthKit)
import HealthKit
#endif

// ═══════════════════════════════════════════════════════════════════
// MARK: - App usage (macOS screen-time equivalent)
// ═══════════════════════════════════════════════════════════════════

/// Reads the JSONL log written by `AppUsageRecorder` and summarises
/// per-app focus time over a configurable window (default 7 days).
public struct AppUsageSource: ScoutSource {
    public let id = "app_usage"
    public let displayName = "App Usage History"
    public let description = "Per-app focus time tracked by the running daemon (macOS equivalent of Screen Time)."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["app_usage.read"]

    public let logURL: URL
    public let window: TimeInterval

    public init(
        logURL: URL = AppUsageRecorder.defaultLogURL(),
        window: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.logURL = logURL
        self.window = window
    }

    public func checkPermission() async throws -> SourcePermissionStatus {
        // The recorder writes to a file in our own ~/.swoosh — no OS
        // permission gate. Permission here is "did the daemon log
        // anything yet?"
        FileManager.default.fileExists(atPath: logURL.path) ? .granted : .denied
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        try await checkPermission()
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cutoff = Date().addingTimeInterval(-window)
        var totals: [String: (display: String, seconds: Double, sessions: Int, last: Date)] = [:]
        for line in text.split(separator: "\n") where !line.isEmpty {
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(AppFocusEvent.self, from: lineData),
                  event.endedAt >= cutoff else { continue }
            var entry = totals[event.bundleID] ?? (event.displayName, 0, 0, .distantPast)
            entry.seconds += event.duration
            entry.sessions += 1
            entry.last = max(entry.last, event.endedAt)
            totals[event.bundleID] = entry
        }

        return totals
            .sorted { $0.value.seconds > $1.value.seconds }
            .map { (bundleID, entry) in
                ScoutRecord(
                    sourceID: id, kind: .appUsage, sensitivity: .high,
                    content: "\(entry.display): \(prettyMinutes(entry.seconds)) over \(entry.sessions) session(s)",
                    metadata: [
                        "bundle_id": bundleID,
                        "seconds": String(Int(entry.seconds)),
                        "sessions": String(entry.sessions),
                        "last_focused": ISO8601DateFormatter().string(from: entry.last),
                        "window_days": String(Int(window / 86400))
                    ]
                )
            }
    }

    private func prettyMinutes(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h\(m)m"
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Focus mode
// ═══════════════════════════════════════════════════════════════════

/// Snapshots the user's current focus mode (Work, Do Not Disturb,
/// Personal, custom). Uses `INFocusStatusCenter` — Intents framework,
/// available cross-platform.
public struct FocusModeSource: ScoutSource {
    public let id = "focus_mode"
    public let displayName = "Focus Mode"
    public let description = "Whether the user is in Do Not Disturb, Work focus, etc."
    public let sensitivity = Sensitivity.medium
    public let requiredPermissions = ["focus_mode.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if canImport(Intents)
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        #if canImport(Intents)
        let status = await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(Intents)
        let status = INFocusStatusCenter.default.focusStatus
        let isFocused = status.isFocused ?? false
        return [
            ScoutRecord(
                sourceID: id, kind: .focusMode, sensitivity: .medium,
                content: isFocused ? "Focus mode is currently active" : "No focus mode active",
                metadata: ["isFocused": String(isFocused)]
            )
        ]
        #else
        return []
        #endif
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Calendar
// ═══════════════════════════════════════════════════════════════════

/// EventKit-backed calendar source. **Deliberately anonymous** — emits
/// aggregate cadence patterns, not titles or attendees. The candidate
/// generator turns these into "User has standing meetings on Wednesday
/// afternoons" memories, never "Meeting with Alice."
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

// ═══════════════════════════════════════════════════════════════════
// MARK: - Reminders
// ═══════════════════════════════════════════════════════════════════

/// EventKit reminders source. Emits load and completion-rate patterns,
/// not item titles. "User typically has ~12 open reminders" is fine;
/// "User has reminder 'call mom'" is not.
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

// ═══════════════════════════════════════════════════════════════════
// MARK: - Recent documents (macOS)
// ═══════════════════════════════════════════════════════════════════

/// Reads `~/Library/Application Support/com.apple.sharedfilelist/` —
/// the on-disk equivalent of "File → Open Recent" across all apps.
/// macOS-only. Records carry a file URL and the app that last touched
/// it; the candidate generator aggregates by file type and surface
/// directory rather than emitting individual paths.
public struct RecentDocumentsSource: ScoutSource {
    public let id = "recent_documents"
    public let displayName = "Recent Documents"
    public let description = "Files surfaced by macOS's per-app Recent Documents lists."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["recent_documents.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if os(macOS)
        let dir = sharedFileListDirectory()
        return FileManager.default.fileExists(atPath: dir.path) ? .granted : .denied
        #else
        return .denied
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        try await checkPermission()
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if os(macOS)
        let dir = sharedFileListDirectory()
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }

        // sharedfilelist files are bookmark-encoded blobs. Without a
        // full bookmark resolver we can still surface useful per-app
        // metadata: which apps the user has recent documents for, and
        // how recently each file list was modified.
        return children.compactMap { url -> ScoutRecord? in
            guard url.pathExtension == "sfl2" || url.pathExtension == "sfl3" else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let modified = (attrs?[.modificationDate] as? Date) ?? .distantPast
            let appHint = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "com.apple.LSSharedFileList.RecentDocuments", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
                .ifEmpty(else: "system")
            return ScoutRecord(
                sourceID: id, kind: .recentDocument, sensitivity: .medium,
                content: "Recent-documents list updated for \(appHint).",
                metadata: [
                    "list": url.lastPathComponent,
                    "modified": ISO8601DateFormatter().string(from: modified)
                ]
            )
        }
        #else
        return []
        #endif
    }

    #if os(macOS)
    private func sharedFileListDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist",
                                    isDirectory: true)
    }
    #endif
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - HealthKit sleep (iOS gated)
// ═══════════════════════════════════════════════════════════════════

/// HealthKit-backed sleep summary. iOS only — macOS has no HealthKit
/// store. Reports total sleep hours per recent night, aggregated.
public struct HealthSleepSource: ScoutSource {
    public let id = "health_sleep"
    public let displayName = "Sleep (HealthKit)"
    public let description = "Recent nightly sleep duration. iOS only; requires Health permissions."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["health.sleep.read"]

    public init() {}

    public func checkPermission() async throws -> SourcePermissionStatus {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        let store = HKHealthStore()
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        switch store.authorizationStatus(for: type) {
        case .sharingAuthorized: return .granted
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
        #else
        return .restricted
        #endif
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        let store = HKHealthStore()
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        try await store.requestAuthorization(toShare: [], read: [type])
        return try await checkPermission()
        #else
        return .restricted
        #endif
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        #if canImport(HealthKit) && os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let store = HKHealthStore()
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        let totalAsleep = samples
            .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let avgPerNight = totalAsleep / 7.0
        let hours = avgPerNight / 3600.0
        return [
            ScoutRecord(
                sourceID: id, kind: .healthSleep, sensitivity: .high,
                content: "Average sleep over the last week: \(String(format: "%.1f", hours)) h/night.",
                metadata: ["avg_hours": String(format: "%.2f", hours)]
            )
        ]
        #else
        return []
        #endif
    }
}

// MARK: - Helpers

private extension String {
    func ifEmpty(else fallback: String) -> String { isEmpty ? fallback : self }
}
