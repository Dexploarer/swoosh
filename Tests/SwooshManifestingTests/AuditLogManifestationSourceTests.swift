// AuditLogManifestationSourceTests.swift — verify the real audit source
// projects and windows tool-audit entries for the mining phase.

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
}
