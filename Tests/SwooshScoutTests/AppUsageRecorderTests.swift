// Tests/SwooshScoutTests/AppUsageRecorderTests.swift — 0.9S Recorder ↔ source round-trip
//
// Verifies that an `AppFocusEvent` written through the encoder used by
// `AppUsageRecorder.append` can be read back through `AppUsageSource.scan`
// and produces a coherent aggregate record. macOS focus capture itself
// (NSWorkspace observer) is not exercised — we only pin the on-disk
// JSONL contract that both sides of the recorder/source pair depend on.

import Foundation
import Testing
@testable import SwooshScout

private func tempLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("swoosh-app-usage-test-\(UUID().uuidString).jsonl")
}

private func writeEvents(_ events: [AppFocusEvent], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var data = Data()
    for event in events {
        data.append(try encoder.encode(event))
        data.append(Data("\n".utf8))
    }
    try data.write(to: url)
}

private func event(
    bundleID: String,
    displayName: String,
    minutesAgoStart: Double,
    duration: TimeInterval
) -> AppFocusEvent {
    let started = Date().addingTimeInterval(-minutesAgoStart * 60)
    return AppFocusEvent(
        bundleID: bundleID,
        displayName: displayName,
        startedAt: started,
        endedAt: started.addingTimeInterval(duration)
    )
}

@Suite("AppUsageRecorder ↔ AppUsageSource on-disk contract")
struct AppUsageRecorderRoundTripTests {

    @Test("Empty log file produces zero records")
    func emptyLog() async throws {
        let url = tempLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)

        let source = AppUsageSource(logURL: url)
        let records = try await source.scan(progress: ScanProgress())
        #expect(records.isEmpty)
    }

    @Test("Missing log file → checkPermission returns .denied, scan returns empty")
    func missingFile() async throws {
        let url = tempLogURL()  // never created
        let source = AppUsageSource(logURL: url)
        #expect(try await source.checkPermission() == .denied)
        let records = try await source.scan(progress: ScanProgress())
        #expect(records.isEmpty)
    }

    @Test("Single event round-trip preserves bundle + duration + sessions")
    func singleEvent() async throws {
        let url = tempLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeEvents(
            [event(bundleID: "com.example.editor", displayName: "Editor", minutesAgoStart: 30, duration: 600)],
            to: url
        )

        let source = AppUsageSource(logURL: url)
        let records = try await source.scan(progress: ScanProgress())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.sourceID == "app_usage")
        #expect(record.kind == .appUsage)
        #expect(record.sensitivity == .high)
        #expect(record.metadata["bundle_id"] == "com.example.editor")
        #expect(record.metadata["sessions"] == "1")
        #expect(record.metadata["seconds"] == "600")
        #expect(record.content.contains("Editor"))
        #expect(record.content.contains("10m"))
    }

    @Test("Multiple sessions of the same bundle aggregate")
    func aggregatesSessions() async throws {
        let url = tempLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeEvents(
            [
                event(bundleID: "com.example.term", displayName: "Term", minutesAgoStart: 60, duration: 300),
                event(bundleID: "com.example.term", displayName: "Term", minutesAgoStart: 30, duration: 900)
            ],
            to: url
        )

        let source = AppUsageSource(logURL: url)
        let records = try await source.scan(progress: ScanProgress())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.metadata["sessions"] == "2")
        #expect(record.metadata["seconds"] == "1200")
    }

    @Test("Multiple bundles are sorted by descending total seconds")
    func sortedByDuration() async throws {
        let url = tempLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeEvents(
            [
                event(bundleID: "com.a", displayName: "A", minutesAgoStart: 30, duration: 60),
                event(bundleID: "com.b", displayName: "B", minutesAgoStart: 30, duration: 900),
                event(bundleID: "com.c", displayName: "C", minutesAgoStart: 30, duration: 300)
            ],
            to: url
        )

        let source = AppUsageSource(logURL: url)
        let records = try await source.scan(progress: ScanProgress())
        let bundleIDs = records.compactMap { $0.metadata["bundle_id"] }
        #expect(bundleIDs == ["com.b", "com.c", "com.a"])
    }

    @Test("Events older than the window are dropped")
    func windowFilter() async throws {
        let url = tempLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeEvents(
            [
                event(bundleID: "com.old", displayName: "Old", minutesAgoStart: 60 * 24 * 30, duration: 600),
                event(bundleID: "com.new", displayName: "New", minutesAgoStart: 30, duration: 600)
            ],
            to: url
        )

        let source = AppUsageSource(logURL: url, window: 24 * 60 * 60)  // last 24h only
        let records = try await source.scan(progress: ScanProgress())
        let bundleIDs = records.compactMap { $0.metadata["bundle_id"] }
        #expect(bundleIDs == ["com.new"])
    }

    @Test("Malformed lines are skipped without throwing")
    func malformedLines() async throws {
        let url = tempLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let good = event(bundleID: "com.ok", displayName: "OK", minutesAgoStart: 5, duration: 120)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        data.append(Data("garbage line not even json\n".utf8))
        data.append(Data("{}\n".utf8))
        data.append(try encoder.encode(good))
        data.append(Data("\n".utf8))
        try data.write(to: url)

        let source = AppUsageSource(logURL: url)
        let records = try await source.scan(progress: ScanProgress())
        #expect(records.count == 1)
        #expect(records.first?.metadata["bundle_id"] == "com.ok")
    }
}
