// AuditLogManifestationSourceTests.swift — 0.1A
// Verify the real audit source projects, windows, and caps tool-audit
// entries for the mining phase.

import Foundation
import Testing
@testable import SwooshManifesting
import SwooshTools

private actor MockAuditLog: AuditLogging {
    private var entries: [AuditEntry]
    init(_ entries: [AuditEntry]) { self.entries = entries }
    func append(_ event: AuditEntry) async throws { entries.append(event) }
    func tail(limit: Int) async -> [AuditEntry] { Array(entries.suffix(max(0, limit))) }
    func search(query: String, limit: Int) async -> [AuditEntry] { [] }
    func getEvent(id: String) async -> AuditEntry? { entries.first { $0.id == id } }
}

@Suite("AuditLogManifestationSource")
struct AuditLogManifestationSourceTests {

    @Test("projects audit entries and windows by cursor")
    func projectsAndWindows() async throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let t2 = Date(timeIntervalSince1970: 3_000)
        let log = MockAuditLog([
            AuditEntry(id: "e0", timestamp: t0, kind: .toolCallStarted,
                       toolName: "git.status", detail: "old"),
            AuditEntry(id: "e1", timestamp: t1, kind: .toolCallSucceeded,
                       toolName: "file.read", detail: "mid"),
            AuditEntry(id: "e2", timestamp: t2, kind: .toolCallSucceeded,
                       toolName: "file.write", detail: "new"),
        ])
        let source = AuditLogManifestationSource(audit: log)

        // No cursor → all three, oldest-first, faithfully projected.
        let all = try await source.eventsSince(nil)
        #expect(all.map(\.id) == ["e0", "e1", "e2"])
        #expect(all[0].kind == "toolCallStarted")
        #expect(all[0].toolName == "git.status")
        #expect(all[0].summary == "old")

        // Cursor → only strictly-later events.
        let since = try await source.eventsSince(t1)
        #expect(since.map(\.id) == ["e2"])
    }

    @Test("empty log yields no events")
    func emptyLog() async throws {
        let source = AuditLogManifestationSource(audit: MockAuditLog([]))
        #expect(try await source.eventsSince(nil).isEmpty)
    }

    @Test("cursor equal to a known timestamp is exclusive")
    func cursorIsStrictlyAfter() async throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let log = MockAuditLog([
            AuditEntry(id: "e0", timestamp: t0, kind: .toolCallStarted,
                       toolName: "git.status", detail: "old"),
            AuditEntry(id: "e1", timestamp: t1, kind: .toolCallSucceeded,
                       toolName: "file.read", detail: "mid"),
        ])
        let source = AuditLogManifestationSource(audit: log)
        // Cursor at the latest event must drop everything at-or-before.
        #expect(try await source.eventsSince(t1).isEmpty)
        // Cursor strictly between t0 and t1 keeps only e1.
        let between = Date(timeIntervalSince1970: 1_500)
        let result = try await source.eventsSince(between)
        #expect(result.map(\.id) == ["e1"])
    }

    @Test("maxEvents caps the tail read")
    func maxEventsCapsTail() async throws {
        // Build 5 entries with strictly increasing timestamps so the
        // suffix(maxEvents=2) trim picks the two newest.
        let base = Date(timeIntervalSince1970: 1_000_000)
        let entries: [AuditEntry] = (0..<5).map { index in
            AuditEntry(
                id: "e\(index)",
                timestamp: base.addingTimeInterval(Double(index) * 60),
                kind: .toolCallSucceeded,
                toolName: "tool.\(index)",
                detail: "row \(index)"
            )
        }
        let log = MockAuditLog(entries)
        let source = AuditLogManifestationSource(audit: log, maxEvents: 2)
        let result = try await source.eventsSince(nil)
        // Tail(limit:2) returns the two newest entries; the source then
        // sorts ascending. Newest two are e3 and e4.
        #expect(result.map(\.id) == ["e3", "e4"])
    }

    @Test("results are always ascending by timestamp")
    func resultsAreAscending() async throws {
        let base = Date(timeIntervalSince1970: 1_000)
        // Insert entries out of order; AuditLog returns them as-stored,
        // and the source must sort.
        let entries: [AuditEntry] = [
            AuditEntry(id: "newest", timestamp: base.addingTimeInterval(300),
                       kind: .toolCallSucceeded, toolName: "z", detail: "z"),
            AuditEntry(id: "oldest", timestamp: base.addingTimeInterval(60),
                       kind: .toolCallSucceeded, toolName: "a", detail: "a"),
            AuditEntry(id: "middle", timestamp: base.addingTimeInterval(120),
                       kind: .toolCallSucceeded, toolName: "m", detail: "m"),
        ]
        let log = MockAuditLog(entries)
        let source = AuditLogManifestationSource(audit: log)
        let result = try await source.eventsSince(nil)
        #expect(result.map(\.id) == ["oldest", "middle", "newest"])
    }
}
