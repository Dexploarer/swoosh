// Tests/SwooshDaemonTests/CodexAuthManagerTests.swift
//
// Pins three slices of the manager that can be unit-tested without
// spawning the real `codex` binary:
//   • State enum wire mapping (raw values match SwooshClient.CodexAuthStatus)
//   • extractURL regex parsing on realistic codex login stdout
//   • snapshot() returns .idle on a freshly-constructed manager
//   • start() fails fast with a clear message when codex isn't installed
//     (run only when no codex is on PATH so we don't actually spawn one)

import Foundation
import Testing
@testable import SwooshDaemonSupport

@Suite("CodexAuthManager.State wire mapping")
struct CodexAuthStateMappingTests {

    @Test("Raw values are the strings the iOS app expects")
    func rawValues() {
        #expect(CodexAuthManager.State.idle.rawValue == "idle")
        #expect(CodexAuthManager.State.pending.rawValue == "pending")
        #expect(CodexAuthManager.State.signedIn.rawValue == "signed_in")
        #expect(CodexAuthManager.State.failed.rawValue == "failed")
        #expect(CodexAuthManager.State.cancelled.rawValue == "cancelled")
    }

    @Test("Codable round-trip preserves every state")
    func codableRoundTrip() throws {
        for state in [CodexAuthManager.State.idle, .pending, .signedIn, .failed, .cancelled] {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(CodexAuthManager.State.self, from: data)
            #expect(decoded == state)
        }
    }
}

@Suite("CodexAuthManager.extractURL")
struct CodexAuthURLParsingTests {

    @Test("Extracts the first https URL from a realistic codex chunk")
    func realisticCodexOutput() {
        let chunk = """
        Codex OAuth — opening browser…
        If the browser does not open automatically, visit:
        https://auth.openai.com/oauth/authorize?client_id=codex&code_challenge=abc&redirect_uri=http://localhost:5173
        Waiting for callback…
        """
        let url = CodexAuthManager.extractURL(chunk)
        #expect(url?.hasPrefix("https://auth.openai.com/oauth/authorize") == true)
    }

    @Test("Returns nil when no URL is present")
    func noURL() {
        #expect(CodexAuthManager.extractURL("Codex login starting…") == nil)
        #expect(CodexAuthManager.extractURL("") == nil)
    }

    @Test("Picks the first URL when multiple appear")
    func firstWins() {
        let chunk = "First: https://first.example.com/path  Then: https://second.example.com"
        let url = CodexAuthManager.extractURL(chunk)
        #expect(url == "https://first.example.com/path")
    }

    @Test("Does not match http:// URLs (https only)")
    func httpOnlyRejected() {
        let chunk = "Open http://insecure.example.com to continue"
        #expect(CodexAuthManager.extractURL(chunk) == nil)
    }

    @Test("Stops at whitespace, doesn't swallow trailing prose")
    func stopsAtWhitespace() {
        let chunk = "Visit https://example.com/x then come back"
        let url = CodexAuthManager.extractURL(chunk)
        #expect(url == "https://example.com/x")
    }
}

@Suite("CodexAuthManager lifecycle")
struct CodexAuthLifecycleTests {

    @Test("Snapshot before any start returns .idle")
    func freshSnapshotIsIdle() async {
        let manager = CodexAuthManager(workingDirectory: FileManager.default.temporaryDirectory)
        let snapshot = await manager.snapshot()
        #expect(snapshot.state == .idle)
        #expect(snapshot.startedAt == nil)
        #expect(snapshot.url == nil)
    }

    @Test("Cancel on idle is a safe no-op")
    func cancelOnIdle() async {
        let manager = CodexAuthManager(workingDirectory: FileManager.default.temporaryDirectory)
        await manager.cancel()
        let snapshot = await manager.snapshot()
        // No process was running → cancel leaves state untouched (.idle).
        #expect(snapshot.state == .idle)
    }
}
