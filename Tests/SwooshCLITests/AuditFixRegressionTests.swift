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

@Suite("DaemonInstallCommand — swooshd path resolution")
struct DaemonInstallPathResolutionTests {
    @Test("Override path is honoured when executable exists")
    func overrideHonoured() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-install-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeSwooshd = tempDir.appendingPathComponent("swooshd")
        FileManager.default.createFile(
            atPath: fakeSwooshd.path,
            contents: Data("#!/bin/sh\nexit 0\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )

        let resolved = DaemonInstallCommand.resolveSwooshdURL(override: fakeSwooshd.path)
        #expect(resolved?.standardizedFileURL == fakeSwooshd.standardizedFileURL)
    }

    @Test("Override path is rejected when binary is missing")
    func overrideRejectedWhenMissing() {
        let bogus = "/tmp/definitely-not-swooshd-\(UUID().uuidString)"
        #expect(DaemonInstallCommand.resolveSwooshdURL(override: bogus) == nil)
    }

    @Test("Empty override falls through to the discovery path")
    func emptyOverrideFallsThrough() {
        // Empty override must not short-circuit the search. We don't pin
        // the actual return value here because that depends on the host
        // environment; we only require the function not to throw and not
        // to return the bogus empty path itself.
        let resolved = DaemonInstallCommand.resolveSwooshdURL(override: "")
        if let resolved {
            #expect(!resolved.path.isEmpty)
        }
    }

    @Test("Generated LaunchAgent plist embeds the resolved swooshd path")
    func plistEmbedsResolvedPath() {
        let plist = DaemonInstallCommand.makeLaunchAgentPlist(
            swooshdPath: "/opt/swoosh/bin/swooshd",
            logsDir: "/Users/test/.swoosh/logs"
        )
        #expect(plist.contains("<string>/opt/swoosh/bin/swooshd</string>"))
        #expect(plist.contains("/Users/test/.swoosh/logs/swooshd.log"))
        #expect(plist.contains("/Users/test/.swoosh/logs/swooshd.err"))
        // Regression assertion: the old hardcoded path must not leak back.
        #expect(!plist.contains("/usr/local/bin/swooshd</string>"))
    }
}
