// Tests/SwooshNetworkPolicyTests/PolicyEnforcedURLSessionEdgeTests.swift — 0.1B Edge cases
//
// Audit follow-ups for `SwooshNetworkPolicy`. Three additional
// regression tests:
//   1. `EgressRequest` preserves the URL port when constructing from
//      a `URLRequest` (currently no rule consults it, but the field is
//      documented as part of the public surface and a future
//      port-restriction rule will rely on it).
//   2. `preflight(request:purpose:)` throws `EgressDeniedError` with a
//      synthetic host when given a `URLRequest` that has no host.
//   3. `evaluate(_:)` continues to return a decision when the auditor
//      `append` throws — failure to log must not corrupt the gate.

import Foundation
import Testing
@testable import SwooshNetworkPolicy
@testable import SwooshTools

@Suite("EgressRequest — URLRequest preserves port + lowercases host/scheme")
struct EgressRequestPortTests {

    @Test("Explicit port survives the URLRequest → EgressRequest conversion")
    func explicitPortPreserved() throws {
        var req = URLRequest(url: try #require(URL(string: "https://api.example.com:8443/v1/x")))
        req.httpMethod = "POST"
        let egress = try #require(EgressRequest(request: req, purpose: "test"))
        #expect(egress.port == 8443)
        #expect(egress.method == "POST")
    }

    @Test("Default port is nil when not present in the URL")
    func defaultPortIsNil() throws {
        let req = URLRequest(url: try #require(URL(string: "https://api.example.com/v1/x")))
        let egress = try #require(EgressRequest(request: req, purpose: "test"))
        #expect(egress.port == nil)
    }

    @Test("Mixed-case host and scheme are normalised to lowercase")
    func hostAndSchemeLowercased() throws {
        let req = URLRequest(url: try #require(URL(string: "HTTPS://API.EXAMPLE.COM/v1")))
        let egress = try #require(EgressRequest(request: req, purpose: "test"))
        #expect(egress.host == "api.example.com")
        #expect(egress.scheme == "https")
    }
}

@Suite("PolicyEnforcedURLSession — preflight error path on no-host URLRequest")
struct PolicyEnforcedURLSessionHostlessTests {

    @Test("Preflight throws synthetic EgressDeniedError when URLRequest has no host")
    func preflightHostlessRequestThrows() async throws {
        let session = PolicyEnforcedURLSession.bypass()
        // A URL with scheme + empty authority slips through URLRequest
        // but produces no host on `URL.host` — the wrapper must reject
        // it with a synthetic `EgressDeniedError` so the caller learns
        // about the missing configuration rather than seeing a generic
        // URLError later.
        let req = URLRequest(url: try #require(URL(string: "https:///path-only")))
        do {
            _ = try await session.data(for: req, purpose: "test")
            Issue.record("Expected denial for hostless URLRequest")
        } catch let error as EgressDeniedError {
            #expect(error.request.host == "<unknown>")
            #expect(error.request.purpose == "test")
            #expect(error.reason.contains("no host"))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}

@Suite("EgressGate — audit failure tolerance")
struct EgressGateAuditFailureTests {

    /// Auditor whose `append` always throws. The gate must still
    /// produce a deterministic decision (not crash, not swallow the
    /// decision) — audit-log failures are tolerated by design via
    /// `try?` in the fanout, and this test pins that contract.
    actor ThrowingAuditor: AuditLogging {
        struct WriteFailure: Error {}
        func append(_ event: AuditEntry) async throws { throw WriteFailure() }
        func tail(limit: Int) async -> [AuditEntry] { [] }
        func search(query: String, limit: Int) async -> [AuditEntry] { [] }
        func getEvent(id: String) async -> AuditEntry? { nil }
    }

    @Test("evaluate still returns the decision when auditor.append throws")
    func auditFailureTolerated() async {
        let gate = EgressGate(configuration: .permissive, auditor: ThrowingAuditor())
        let decision = await gate.evaluate(
            EgressRequest(host: "api.example.com", port: nil, scheme: "https", method: "GET", purpose: "test")
        )
        #expect(decision == .allow)
    }

    @Test("Deny decisions also survive an auditor that throws")
    func denyWithFailingAuditor() async {
        let gate = EgressGate(
            configuration: EgressGateConfiguration(denylist: ["bad.example"]),
            auditor: ThrowingAuditor()
        )
        let decision = await gate.evaluate(
            EgressRequest(host: "bad.example", port: nil, scheme: "https", method: "GET", purpose: "test")
        )
        #expect(!decision.isAllowed)
    }
}
