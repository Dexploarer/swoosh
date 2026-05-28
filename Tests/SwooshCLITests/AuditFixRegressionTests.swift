// Tests/SwooshCLITests/AuditFixRegressionTests.swift — Audit-driven regressions — 0.4A
//
// Pins the three SwooshCLI fixes flagged by the directory audit:
//   1. `swoosh memory list --status rejected` filter (was pattern-matching
//      `.pending` against `MemoryRow.rejected`, silently returning empty)
//   2. `swoosh daemon install` swooshd-path resolution (was hardcoding
//      `/usr/local/bin/swooshd` regardless of where the binary lived)
//   3. The dead `swoosh chat --continue` flag removal
//
// Tests for (3) live in CommandParsingTests; this file covers (1) and (2).

import Testing
import Foundation
import SwooshTools
@testable import SwooshCLI

@Suite("MemoryListCommand — rejected filter")
struct RejectedMemoryFilterTests {
    private static func candidate(id: String, status: CandidateStatus) -> MemoryCandidate {
        MemoryCandidate(
            id: id,
            text: "candidate \(id)",
            category: .fact,
            sensitivity: .normal,
            confidence: 0.5,
            evidence: [],
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_716_422_400)
        )
    }

    @Test("MemoryListCommand.rejectedCandidates extracts payloads from .rejected candidates")
    func extractsRejectedOnly() {
        let pending = Self.candidate(id: "c-pending", status: .pending)
        let rejected = Self.candidate(id: "c-rejected", status: .rejected)
        let approved = Self.candidate(id: "c-approved", status: .approved)

        let result = MemoryListCommand.rejectedCandidates(from: [approved, pending, rejected])
        #expect(result.count == 1)
        #expect(result.first?.id == "c-rejected")
    }

    @Test("MemoryListCommand.rejectedCandidates returns empty when no .rejected candidates")
    func noRejectedRows() {
        let pending = Self.candidate(id: "c1", status: .pending)
        #expect(MemoryListCommand.rejectedCandidates(from: [pending]).isEmpty)
    }

    @Test("MemoryListCommand.rejectedCandidates returns empty for empty input")
    func emptyInput() {
        #expect(MemoryListCommand.rejectedCandidates(from: []).isEmpty)
    }
}

// The "DaemonInstallCommand — swooshd path resolution" suite was removed
// with the launchd lifecycle commands: the agent runtime is hosted
// in-process by the macOS app, so there is no swooshd binary to resolve
// or LaunchAgent plist to generate.
