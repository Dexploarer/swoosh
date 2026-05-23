// Tests/SwooshNetworkPolicyTests/EgressGateTests.swift — 0.1A Gate decision matrix

import Foundation
import Testing
@testable import SwooshNetworkPolicy
@testable import SwooshTools

@Suite("EgressGate decisions")
struct EgressGateTests {

    private func req(
        _ host: String,
        scheme: String = "https",
        method: String = "GET",
        purpose: String = "test"
    ) -> EgressRequest {
        EgressRequest(host: host, port: nil, scheme: scheme, method: method, purpose: purpose)
    }

    @Test("Permissive default allows every host")
    func permissiveAllowsEverything() async {
        let gate = EgressGate(configuration: .permissive)
        let decision = await gate.evaluate(req("api.openai.com"))
        #expect(decision == .allow)
        let decision2 = await gate.evaluate(req("evil.example"))
        #expect(decision2 == .allow)
    }

    @Test("Denylist exact match blocks the host")
    func denylistExactBlocks() async {
        let gate = EgressGate(configuration: EgressGateConfiguration(denylist: ["bad.example"]))
        let decision = await gate.evaluate(req("bad.example"))
        if case let .deny(reason) = decision {
            #expect(reason.contains("denylist"))
        } else {
            Issue.record("Expected deny, got \(decision)")
        }
    }

    @Test("Denylist leading-dot wildcard matches subdomains and the apex")
    func denylistWildcard() async {
        let gate = EgressGate(configuration: EgressGateConfiguration(denylist: [".tracker.example"]))
        let apex = await gate.evaluate(req("tracker.example"))
        let sub = await gate.evaluate(req("pixel.tracker.example"))
        let other = await gate.evaluate(req("nottracker.example"))
        #expect(apex.isAllowed == false)
        #expect(sub.isAllowed == false)
        #expect(other.isAllowed == true)
    }

    @Test("Denylist match is case-insensitive on the host")
    func denylistCaseInsensitive() async {
        let gate = EgressGate(configuration: EgressGateConfiguration(denylist: ["bad.example"]))
        let upper = await gate.evaluate(req("BAD.EXAMPLE"))
        #expect(upper.isAllowed == false)
    }

    @Test("Allowlist forces strict mode")
    func allowlistStrict() async {
        let gate = EgressGate(configuration: EgressGateConfiguration(allowlist: ["api.openai.com"]))
        let allowed = await gate.evaluate(req("api.openai.com"))
        let denied = await gate.evaluate(req("api.other.com"))
        #expect(allowed.isAllowed == true)
        #expect(denied.isAllowed == false)
    }

    @Test("Allowlist + denylist: denylist wins")
    func denylistTrumps() async {
        let gate = EgressGate(configuration: EgressGateConfiguration(
            allowlist: ["api.openai.com"],
            denylist: ["api.openai.com"]
        ))
        let decision = await gate.evaluate(req("api.openai.com"))
        #expect(decision.isAllowed == false)
    }

    @Test("HTTPS-only rejects http URLs")
    func httpsOnly() async {
        let gate = EgressGate(configuration: EgressGateConfiguration(httpsOnly: true))
        let http = await gate.evaluate(req("api.openai.com", scheme: "http"))
        let https = await gate.evaluate(req("api.openai.com", scheme: "https"))
        if case let .deny(reason) = http {
            #expect(reason.contains("Non-HTTPS"))
        } else {
            Issue.record("Expected deny for http, got \(http)")
        }
        #expect(https.isAllowed == true)
    }

    @Test("reconfigure swaps the rule set live")
    func reconfigureLive() async {
        let gate = EgressGate(configuration: .permissive)
        #expect((await gate.evaluate(req("anywhere"))).isAllowed)
        await gate.reconfigure(EgressGateConfiguration(allowlist: ["api.openai.com"]))
        #expect((await gate.evaluate(req("anywhere"))).isAllowed == false)
        #expect((await gate.evaluate(req("api.openai.com"))).isAllowed)
    }

    @Test("Configuration round-trips through currentConfiguration")
    func configurationRoundtrip() async {
        let original = EgressGateConfiguration(allowlist: ["api.openai.com"], denylist: ["bad.example"], httpsOnly: true)
        let gate = EgressGate(configuration: original)
        let read = await gate.currentConfiguration()
        #expect(read == original)
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Audit fanout
// ═══════════════════════════════════════════════════════════════════

/// In-memory `AuditLogging` for verifying the gate's fanout.
actor CollectingAuditor: AuditLogging {
    private var entries: [AuditEntry] = []

    func append(_ event: AuditEntry) async throws {
        entries.append(event)
    }

    func tail(limit: Int) async -> [AuditEntry] {
        Array(entries.suffix(limit))
    }

    func search(query: String, limit: Int) async -> [AuditEntry] {
        entries.filter { $0.detail.contains(query) }.suffix(limit).map { $0 }
    }

    func getEvent(id: String) async -> AuditEntry? {
        entries.first { $0.id == id }
    }

    func snapshot() async -> [AuditEntry] {
        entries
    }
}

@Suite("EgressGate audit fanout")
struct EgressGateAuditTests {

    private func req(_ host: String, scheme: String = "https") -> EgressRequest {
        EgressRequest(host: host, port: nil, scheme: scheme, method: "GET", purpose: "provider:openai")
    }

    @Test("Allow decisions emit a toolCallStarted audit entry")
    func allowEmits() async throws {
        let auditor = CollectingAuditor()
        let gate = EgressGate(configuration: .permissive, auditor: auditor)
        _ = await gate.evaluate(req("api.openai.com"))
        let snapshot = await auditor.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.kind == .toolCallStarted)
        #expect(snapshot.first?.detail.contains("egress.allow") == true)
        #expect(snapshot.first?.detail.contains("api.openai.com") == true)
        #expect(snapshot.first?.detail.contains("provider:openai") == true)
        #expect(snapshot.first?.success == true)
    }

    @Test("Deny decisions emit a permissionDenied audit entry with reason")
    func denyEmits() async throws {
        let auditor = CollectingAuditor()
        let gate = EgressGate(
            configuration: EgressGateConfiguration(denylist: ["bad.example"]),
            auditor: auditor
        )
        _ = await gate.evaluate(req("bad.example"))
        let snapshot = await auditor.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.kind == .permissionDenied)
        #expect(snapshot.first?.detail.contains("egress.deny") == true)
        #expect(snapshot.first?.detail.contains("denylist") == true)
        #expect(snapshot.first?.success == false)
    }
}
