// Tests/SwooshNetworkPolicyTests/PolicyEnforcedURLSessionTests.swift — 0.1A Preflight tests

import Foundation
import Testing
@testable import SwooshNetworkPolicy

@Suite("PolicyEnforcedURLSession preflight")
struct PolicyEnforcedURLSessionTests {

    private func request(_ urlString: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = method
        return req
    }

    @Test("EgressRequest extracts host/scheme/method from URLRequest")
    func egressRequestFromURLRequest() {
        let r = request("https://api.openai.com:443/v1/chat", method: "POST")
        let egress = EgressRequest(request: r, purpose: "provider:openai")
        #expect(egress?.host == "api.openai.com")
        #expect(egress?.port == 443)
        #expect(egress?.scheme == "https")
        #expect(egress?.method == "POST")
        #expect(egress?.purpose == "provider:openai")
    }

    @Test("EgressRequest is nil when URLRequest has no host")
    func egressRequestNoHost() {
        let r = URLRequest(url: URL(string: "https:///path-only")!)
        let egress = EgressRequest(request: r, purpose: "test")
        #expect(egress == nil)
    }

    @Test("Bypass session allows any request")
    func bypassAllows() async throws {
        let session = PolicyEnforcedURLSession.bypass()
        // preflight succeeds for an allowed egress
        try await session.preflight(EgressRequest(host: "api.openai.com", port: nil, scheme: "https", method: "GET", purpose: "test"))
    }

    @Test("Deny-all policy throws EgressDeniedError on preflight")
    func denyAllThrows() async {
        let session = PolicyEnforcedURLSession(policy: DenyAllNetworkPolicy(reason: "test deny"))
        let egress = EgressRequest(host: "api.openai.com", port: nil, scheme: "https", method: "GET", purpose: "test")
        do {
            try await session.preflight(egress)
            Issue.record("Expected throw")
        } catch let error as EgressDeniedError {
            #expect(error.reason == "test deny")
            #expect(error.request.host == "api.openai.com")
            #expect(error.request.purpose == "test")
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("EgressDeniedError description includes scheme, host, purpose, reason")
    func deniedErrorDescription() {
        let egress = EgressRequest(host: "api.openai.com", port: nil, scheme: "https", method: "GET", purpose: "provider:openai")
        let err = EgressDeniedError(request: egress, reason: "Not on allowlist.")
        let text = err.description
        #expect(text.contains("https://api.openai.com"))
        #expect(text.contains("provider:openai"))
        #expect(text.contains("Not on allowlist"))
    }
}
