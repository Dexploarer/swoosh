// Tests/SwooshNetworkPolicyTests/NetworkPolicyTests.swift — 0.8B

import Testing
import Foundation
@testable import SwooshNetworkPolicy
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Trust Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Remote Trust Policy")
struct RemoteTrustPolicyTests {

    @Test("Default is untrusted remote")
    func defaultUntrusted() {
        let policy = RemoteServerTrustPolicy.safeDefault
        #expect(policy.level == .untrustedRemote)
    }

    @Test("HTTPS required by default")
    func httpsRequired() {
        #expect(RemoteServerTrustPolicy.safeDefault.requireHTTPS)
    }

    @Test("Self-signed certs rejected by default")
    func selfSignedRejected() {
        #expect(!RemoteServerTrustPolicy.safeDefault.allowSelfSignedCertificate)
    }

    @Test("Capability changes require approval by default")
    func capabilityApprovalRequired() {
        #expect(RemoteServerTrustPolicy.safeDefault.requireUserApprovalForCapabilityChanges)
    }

    @Test("Denied host blocked")
    func deniedHostBlocked() {
        var policy = RemoteServerTrustPolicy.safeDefault
        policy.deniedHosts = ["evil.example.com"]
        #expect(!policy.isHostAllowed("evil.example.com"))
    }

    @Test("Allowed host passes")
    func allowedHostPasses() {
        var policy = RemoteServerTrustPolicy.safeDefault
        policy.allowedHosts = ["trusted.example.com"]
        #expect(policy.isHostAllowed("trusted.example.com"))
        #expect(!policy.isHostAllowed("other.example.com"))
    }

    @Test("Certificate pin verified")
    func certPinVerified() {
        var policy = RemoteServerTrustPolicy.safeDefault
        policy.pinnedCertificateFingerprints = ["sha256:abc123"]
        #expect(policy.isCertificatePinned("sha256:abc123"))
        #expect(!policy.isCertificatePinned("sha256:xyz789"))
    }

    @Test("No pins = all pass")
    func noPinsAllPass() {
        let policy = RemoteServerTrustPolicy.safeDefault
        #expect(policy.isCertificatePinned("anything"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Network Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Network Policy")
struct NetworkPolicyTests {

    @Test("Remote HTTP disabled by default")
    func remoteHTTPDisabled() {
        #expect(!RemoteNetworkPolicy.safeDefault.allowRemoteHTTP)
    }

    @Test("HTTP endpoint rejected")
    func httpEndpointRejected() {
        let policy = RemoteNetworkPolicy.safeDefault
        #expect(!policy.isEndpointAllowed("http://remote.example.com/mcp"))
    }

    @Test("HTTPS endpoint allowed")
    func httpsAllowed() {
        let policy = RemoteNetworkPolicy.safeDefault
        #expect(policy.isEndpointAllowed("https://remote.example.com/mcp"))
    }

    @Test("Localhost HTTP allowed when localhostRemoteProfile enabled")
    func localhostHTTPAllowed() {
        let policy = RemoteNetworkPolicy.safeDefault
        #expect(policy.isEndpointAllowed("http://localhost:3000/mcp"))
        #expect(policy.isEndpointAllowed("http://127.0.0.1:3000/mcp"))
    }

    @Test("Private network hosts detected")
    func privateNetworkDetected() {
        let policy = RemoteNetworkPolicy.safeDefault
        #expect(policy.isPrivateNetworkHost("192.168.1.1"))
        #expect(policy.isPrivateNetworkHost("10.0.0.1"))
        #expect(policy.isPrivateNetworkHost("172.16.0.1"))
        #expect(!policy.isPrivateNetworkHost("8.8.8.8"))
    }

    @Test("Private network hosts blocked by default")
    func privateNetworkBlocked() {
        #expect(!RemoteNetworkPolicy.safeDefault.allowPrivateNetworkHosts)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Identity Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Remote Identity")
struct RemoteIdentityTests {

    @Test("Identity created")
    func identityCreated() {
        let id = RemoteServerIdentity(
            serverID: "linear", endpoint: "https://linear.example/mcp",
            host: "linear.example", tlsCertificateFingerprint: "sha256:abc"
        )
        #expect(id.host == "linear.example")
        #expect(id.tlsCertificateFingerprint == "sha256:abc")
    }

    @Test("Identity change detected — host")
    func hostChanged() {
        let v = IdentityValidator()
        let old = RemoteServerIdentity(serverID: "s1", endpoint: "https://a.com", host: "a.com")
        let new = RemoteServerIdentity(serverID: "s1", endpoint: "https://b.com", host: "b.com")
        let changes = v.detectChanges(stored: old, current: new)
        #expect(changes.contains { $0.field == "host" })
    }

    @Test("Identity change detected — certificate")
    func certChanged() {
        let v = IdentityValidator()
        let old = RemoteServerIdentity(serverID: "s1", endpoint: "https://a.com", host: "a.com",
            tlsCertificateFingerprint: "sha256:old")
        let new = RemoteServerIdentity(serverID: "s1", endpoint: "https://a.com", host: "a.com",
            tlsCertificateFingerprint: "sha256:new")
        let changes = v.detectChanges(stored: old, current: new)
        #expect(changes.contains { $0.field == "tlsCertificateFingerprint" })
    }

    @Test("Identity change detected — issuer")
    func issuerChanged() {
        let v = IdentityValidator()
        let old = RemoteServerIdentity(serverID: "s1", endpoint: "https://a.com", host: "a.com",
            authorizationServerIssuer: "https://auth1.com")
        let new = RemoteServerIdentity(serverID: "s1", endpoint: "https://a.com", host: "a.com",
            authorizationServerIssuer: "https://auth2.com")
        let changes = v.detectChanges(stored: old, current: new)
        #expect(changes.contains { $0.field == "authorizationServerIssuer" })
    }

    @Test("No changes when identical")
    func noChanges() {
        let v = IdentityValidator()
        let id = RemoteServerIdentity(serverID: "s1", endpoint: "https://a.com", host: "a.com")
        let changes = v.detectChanges(stored: id, current: id)
        #expect(changes.isEmpty)
    }
}
